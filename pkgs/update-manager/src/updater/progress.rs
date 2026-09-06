//! Nix's `--log-format internal-json` stream, and what to make of it.
//!
//! Every stderr line is `@nix {json}`. The records that matter here, with the
//! numeric codes nix uses (`ActivityType` and `ResultType` in its logging.hh):
//!
//! - `start`, `type` 103 (*copyPaths*) and 104 (*builds*): the two aggregate
//!   activities whose `progress` results are the counters -- paths fetched and
//!   derivations built -- that `nix build --dry-run` promised. That is why the
//!   fraction is computed from those two and nothing else: it is exact, it is
//!   monotonic, and it reaches 1 exactly when nix is done.
//! - `start`, `type` 105 (*build*): one derivation; `fields[0]` is its path.
//! - `start`, `type` 101 (*fileTransfer*): one download; its `progress` is in
//!   bytes. Summed for display only.
//! - `result`, `type` 105: progress `[done, expected, running, failed]`.
//! - `result`, `type` 106: setExpected. Parsed, deliberately **not** used: the
//!   root activity's expected bytes grow as substituter queries come in (0 →
//!   234 KiB → 30 MiB → 33 MiB on a five-path build), so a fraction built on
//!   them runs backwards early on.
//! - `result`, `type` 104: setPhase ("unpackPhase", "buildPhase", …).
//! - `result`, `type` 101: one build log line.
//! - `msg`: nix's own messages; level 0 is `error`, 1 `warn`.
//!
//! A five-path build emits close to seven thousand of these, so nothing here
//! talks to the tray or the notification server; the caller throttles.

use std::collections::{HashMap, VecDeque};

use serde_json::Value;
use stewos_update_manager::BuildPlan;

use super::strip_ansi;
use crate::state::Progress;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActivityKind {
    CopyPath,
    FileTransfer,
    Realise,
    CopyPaths,
    Builds,
    Build,
    Substitute,
    QueryPathInfo,
    Other(u64),
}

impl ActivityKind {
    fn from_code(code: u64) -> Self {
        match code {
            100 => ActivityKind::CopyPath,
            101 => ActivityKind::FileTransfer,
            102 => ActivityKind::Realise,
            103 => ActivityKind::CopyPaths,
            104 => ActivityKind::Builds,
            105 => ActivityKind::Build,
            108 => ActivityKind::Substitute,
            109 => ActivityKind::QueryPathInfo,
            other => ActivityKind::Other(other),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Start {
        id: u64,
        kind: ActivityKind,
        text: String,
        /// `fields[0]` when it is a string: the store path the activity is
        /// about, for builds, copies and substitutions.
        path: Option<String>,
    },
    Progress {
        id: u64,
        done: u64,
        expected: u64,
        running: u64,
        failed: u64,
    },
    SetExpected {
        id: u64,
        kind: ActivityKind,
        expected: u64,
    },
    SetPhase {
        id: u64,
        phase: String,
    },
    BuildLogLine {
        id: u64,
        line: String,
    },
    Stop {
        id: u64,
    },
    Msg {
        level: u64,
        text: String,
    },
}

fn num(value: Option<&Value>) -> u64 {
    match value {
        Some(Value::Number(n)) => n
            .as_u64()
            .or_else(|| n.as_f64().map(|f| f as u64))
            .unwrap_or(0),
        _ => 0,
    }
}

fn text(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_str)
        .map(strip_ansi)
        .unwrap_or_default()
}

/// One stderr line to one event. Anything that is not an `@nix` record we
/// understand is `None`; the caller keeps the raw line for the failure report.
pub fn parse_line(line: &str) -> Option<Event> {
    let json = line.strip_prefix("@nix ")?;
    let v: Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(err) => {
            log::debug!("unparseable nix log record: {err}: {json}");
            return None;
        }
    };
    let fields: &[Value] = v
        .get("fields")
        .and_then(Value::as_array)
        .map_or(&[], Vec::as_slice);
    let id = num(v.get("id"));
    let kind = num(v.get("type"));
    match v.get("action")?.as_str()? {
        "start" => Some(Event::Start {
            id,
            kind: ActivityKind::from_code(kind),
            text: text(v.get("text")),
            path: fields.first().and_then(Value::as_str).map(str::to_string),
        }),
        "result" => match kind {
            101 => Some(Event::BuildLogLine {
                id,
                line: text(fields.first()),
            }),
            104 => Some(Event::SetPhase {
                id,
                phase: text(fields.first()),
            }),
            105 => Some(Event::Progress {
                id,
                done: num(fields.first()),
                expected: num(fields.get(1)),
                running: num(fields.get(2)),
                failed: num(fields.get(3)),
            }),
            106 => Some(Event::SetExpected {
                id,
                kind: ActivityKind::from_code(num(fields.first())),
                expected: num(fields.get(1)),
            }),
            _ => None,
        },
        "stop" => Some(Event::Stop { id }),
        "msg" => Some(Event::Msg {
            level: num(v.get("level")),
            text: text(v.get("msg")),
        }),
        _ => None,
    }
}

/// "/nix/store/<hash>-python3.12-requests-2.31.0.drv" → "python3.12-requests":
/// the store name cut where `parseDrvName` cuts it, at the first dash that is
/// followed by a digit.
pub fn drv_pname(drv_path: &str) -> String {
    let base = drv_path.rsplit('/').next().unwrap_or(drv_path);
    let base = base.strip_suffix(".drv").unwrap_or(base);
    let name = match base.char_indices().nth(32) {
        Some((32, '-')) if base.is_char_boundary(33) => &base[33..],
        _ => base,
    };
    let bytes = name.as_bytes();
    let cut = (0..bytes.len().saturating_sub(1))
        .find(|&i| bytes[i] == b'-' && bytes[i + 1].is_ascii_digit())
        .unwrap_or(name.len());
    name[..cut].to_string()
}

/// A bounded tail of lines, kept under a byte budget.
struct Tail {
    lines: VecDeque<String>,
    bytes: usize,
    max: usize,
}

impl Tail {
    fn new(max: usize) -> Self {
        Self {
            lines: VecDeque::new(),
            bytes: 0,
            max,
        }
    }

    fn push(&mut self, line: String) {
        self.bytes += line.len() + 1;
        self.lines.push_back(line);
        while self.bytes > self.max {
            match self.lines.pop_front() {
                Some(dropped) => self.bytes -= dropped.len() + 1,
                None => break,
            }
        }
    }

    fn join(&self) -> String {
        self.lines
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>()
            .join("\n")
    }
}

#[derive(Default, Clone, Copy)]
struct Done {
    paths: u64,
    drvs: u64,
    bytes: u64,
}

/// Accumulates one build operation's events. Spans both `nix build` runs of
/// an operation: [`Tracker::finish_build`] folds the first run's counters in
/// so the second starts from where it left off, against the one shared plan.
pub struct Tracker {
    kinds: HashMap<u64, ActivityKind>,
    /// Latest `done` per transfer, so a re-sent figure is not counted twice.
    transfers: HashMap<u64, u64>,
    base: Done,
    cur: Done,
    /// Running builds, in start order; the last is "current".
    builds: Vec<(u64, String)>,
    phases: HashMap<u64, String>,
    failed: u64,
    /// The last build log lines, for the failure report. Sized with the
    /// report's `MAX_ERROR` in mind: both tails together stay under it.
    log: Tail,
    /// Nix's own error and warning messages.
    errors: Tail,
}

impl Default for Tracker {
    fn default() -> Self {
        Self::new()
    }
}

impl Tracker {
    pub fn new() -> Self {
        Self {
            kinds: HashMap::new(),
            transfers: HashMap::new(),
            base: Done::default(),
            cur: Done::default(),
            builds: Vec::new(),
            phases: HashMap::new(),
            failed: 0,
            log: Tail::new(16 * 1024),
            errors: Tail::new(8 * 1024),
        }
    }

    pub fn apply(&mut self, event: &Event) {
        match event {
            Event::Start {
                id,
                kind,
                text,
                path,
            } => {
                self.kinds.insert(*id, *kind);
                if *kind == ActivityKind::Build {
                    let name = path
                        .as_deref()
                        .map(drv_pname)
                        .unwrap_or_else(|| text.clone());
                    self.builds.push((*id, name));
                }
            }
            Event::Progress {
                id, done, failed, ..
            } => match self.kinds.get(id) {
                Some(ActivityKind::CopyPaths) => self.cur.paths = *done,
                Some(ActivityKind::Builds) => {
                    self.cur.drvs = *done;
                    self.failed = *failed;
                }
                Some(ActivityKind::FileTransfer) => {
                    let previous = self.transfers.insert(*id, *done).unwrap_or(0);
                    self.cur.bytes = self.cur.bytes + *done - previous.min(*done);
                }
                _ => {}
            },
            Event::SetExpected { .. } => {}
            Event::SetPhase { id, phase } => {
                self.phases.insert(*id, phase.clone());
            }
            Event::BuildLogLine { line, .. } => self.log.push(line.clone()),
            Event::Stop { id } => {
                self.builds.retain(|(build, _)| build != id);
                self.phases.remove(id);
            }
            Event::Msg { level, text } => {
                if *level <= 1 && !text.is_empty() {
                    self.errors.push(text.clone());
                }
            }
        }
    }

    /// A stderr line that was not a record at all. Kept with the log.
    pub fn note_raw(&mut self, line: &str) {
        if !line.trim().is_empty() {
            self.log.push(strip_ansi(line));
        }
    }

    /// Between the two `nix build` runs of one operation.
    pub fn finish_build(&mut self) {
        self.base.paths += self.cur.paths;
        self.base.drvs += self.cur.drvs;
        self.base.bytes += self.cur.bytes;
        self.cur = Done::default();
        self.kinds.clear();
        self.transfers.clear();
        self.builds.clear();
        self.phases.clear();
    }

    pub fn snapshot(&self, plan: &BuildPlan) -> Progress {
        let current = self.builds.last();
        Progress {
            plan: *plan,
            paths_done: self.base.paths + self.cur.paths,
            drvs_done: self.base.drvs + self.cur.drvs,
            bytes_done: self.base.bytes + self.cur.bytes,
            current: current.map(|(_, name)| name.clone()),
            phase: current.and_then(|(id, _)| self.phases.get(id).cloned()),
            failed: self.failed,
        }
    }

    /// What to put in the error: nix's messages, then the tail of the build
    /// log. Bounded, so `troubleshoot::elide` never has to cut it.
    pub fn failure_text(&self) -> String {
        let errors = self.errors.join();
        let log = self.log.join();
        match (errors.is_empty(), log.is_empty()) {
            (true, true) => "nix printed nothing".to_string(),
            (false, true) => errors,
            (true, false) => format!("--- last build log lines ---\n{log}"),
            (false, false) => format!("{errors}\n--- last build log lines ---\n{log}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan(paths: u32, derivations: u32) -> BuildPlan {
        BuildPlan {
            paths,
            derivations,
            download_bytes: 10_000,
            unpacked_bytes: 0,
        }
    }

    fn start(id: u64, kind: ActivityKind) -> Event {
        Event::Start {
            id,
            kind,
            text: String::new(),
            path: None,
        }
    }

    fn progress(id: u64, done: u64, expected: u64) -> Event {
        Event::Progress {
            id,
            done,
            expected,
            running: 0,
            failed: 0,
        }
    }

    #[test]
    fn parses_each_record_kind() {
        let start = parse_line(
            r#"@nix {"action":"start","fields":["/nix/store/abcdefghijklmnopqrstuvwxyz012345-hello-2.12.1.drv"],"id":7,"level":3,"parent":0,"text":"building hello","type":105}"#,
        );
        assert_eq!(
            start,
            Some(Event::Start {
                id: 7,
                kind: ActivityKind::Build,
                text: "building hello".into(),
                path: Some(
                    "/nix/store/abcdefghijklmnopqrstuvwxyz012345-hello-2.12.1.drv".into()
                ),
            })
        );
        assert_eq!(
            parse_line(
                r#"@nix {"action":"result","fields":[5,5,0,0],"id":150813481631749,"type":105}"#
            ),
            Some(Event::Progress {
                id: 150813481631749,
                done: 5,
                expected: 5,
                running: 0,
                failed: 0
            })
        );
        assert_eq!(
            parse_line(r#"@nix {"action":"result","fields":[101,10216100],"id":3,"type":106}"#),
            Some(Event::SetExpected {
                id: 3,
                kind: ActivityKind::FileTransfer,
                expected: 10_216_100
            })
        );
        assert_eq!(
            parse_line(r#"@nix {"action":"result","fields":["buildPhase"],"id":7,"type":104}"#),
            Some(Event::SetPhase {
                id: 7,
                phase: "buildPhase".into()
            })
        );
        // Colour inside a record is stripped like everywhere else.
        assert_eq!(
            parse_line(
                r#"@nix {"action":"result","fields":["\u001b[1mcc -O2\u001b[0m"],"id":7,"type":101}"#
            ),
            Some(Event::BuildLogLine {
                id: 7,
                line: "cc -O2".into()
            })
        );
        assert_eq!(
            parse_line(r#"@nix {"action":"stop","id":7}"#),
            Some(Event::Stop { id: 7 })
        );
        assert_eq!(
            parse_line(r#"@nix {"action":"msg","level":0,"msg":"\u001b[31;1merror:\u001b[0m boom"}"#),
            Some(Event::Msg {
                level: 0,
                text: "error: boom".into()
            })
        );
    }

    #[test]
    fn rejects_what_it_does_not_understand() {
        assert_eq!(
            parse_line("copying path '/nix/store/x' from 'https://cache.nixos.org'..."),
            None
        );
        assert_eq!(parse_line(r#"@nix {"action":"start","id":1,"type":10"#), None);
        assert_eq!(
            parse_line(r#"@nix {"action":"result","fields":[1],"id":1,"type":999}"#),
            None
        );
        assert_eq!(parse_line(r#"@nix {"action":"dance"}"#), None);
    }

    #[test]
    fn counts_paths_and_builds_across_two_runs() {
        let mut t = Tracker::new();
        let p = plan(10, 4);

        t.apply(&start(1, ActivityKind::CopyPaths));
        t.apply(&start(2, ActivityKind::Builds));
        t.apply(&progress(1, 6, 6));
        t.apply(&progress(2, 1, 1));
        assert_eq!(t.snapshot(&p).percent(), 50);
        t.finish_build();

        // The second run's aggregates restart from zero.
        t.apply(&start(1, ActivityKind::CopyPaths));
        t.apply(&start(2, ActivityKind::Builds));
        t.apply(&progress(1, 4, 4));
        t.apply(&progress(2, 3, 3));
        let s = t.snapshot(&p);
        assert_eq!((s.paths_done, s.drvs_done), (10, 4));
        assert_eq!(s.percent(), 100);
    }

    #[test]
    fn bytes_are_the_latest_figure_per_transfer_not_a_sum_of_reports() {
        let mut t = Tracker::new();
        t.apply(&start(9, ActivityKind::FileTransfer));
        t.apply(&progress(9, 100, 600));
        t.apply(&progress(9, 100, 600));
        t.apply(&progress(9, 600, 600));
        assert_eq!(t.snapshot(&plan(1, 0)).bytes_done, 600);
    }

    #[test]
    fn the_fraction_clamps_and_an_empty_plan_is_done() {
        let mut t = Tracker::new();
        t.apply(&start(1, ActivityKind::CopyPaths));
        t.apply(&progress(1, 12, 12));
        assert_eq!(t.snapshot(&plan(10, 0)).fraction(), 1.0);
        assert_eq!(Tracker::new().snapshot(&plan(0, 0)).fraction(), 1.0);
    }

    #[test]
    fn tracks_the_current_build_and_its_phase() {
        let mut t = Tracker::new();
        t.apply(&Event::Start {
            id: 7,
            kind: ActivityKind::Build,
            text: String::new(),
            path: Some("/nix/store/abcdefghijklmnopqrstuvwxyz012345-firefox-155.0.drv".into()),
        });
        t.apply(&Event::SetPhase {
            id: 7,
            phase: "buildPhase".into(),
        });
        let s = t.snapshot(&plan(0, 1));
        assert_eq!(s.current.as_deref(), Some("firefox"));
        assert_eq!(s.phase.as_deref(), Some("buildPhase"));
        t.apply(&Event::Stop { id: 7 });
        assert_eq!(t.snapshot(&plan(0, 1)).current, None);
    }

    #[test]
    fn pnames_are_cut_where_nix_cuts_them() {
        assert_eq!(
            drv_pname(
                "/nix/store/abcdefghijklmnopqrstuvwxyz012345-python3.12-requests-2.31.0.drv"
            ),
            "python3.12-requests"
        );
        assert_eq!(
            drv_pname(
                "/nix/store/abcdefghijklmnopqrstuvwxyz012345-nixos-system-host-26.11.20260904.801bef6.drv"
            ),
            "nixos-system-host"
        );
        assert_eq!(
            drv_pname("/nix/store/abcdefghijklmnopqrstuvwxyz012345-nixvim.drv"),
            "nixvim"
        );
        assert_eq!(drv_pname("hello-2.12.1"), "hello");
    }

    #[test]
    fn the_failure_text_stays_bounded() {
        let mut t = Tracker::new();
        for i in 0..100_000 {
            t.apply(&Event::BuildLogLine {
                id: 1,
                line: format!("log line {i} with some padding text"),
            });
        }
        for i in 0..10_000 {
            t.apply(&Event::Msg {
                level: 0,
                text: format!("error number {i}"),
            });
        }
        let text = t.failure_text();
        assert!(text.len() < 24 * 1024 + 64, "{}", text.len());
        assert!(text.ends_with("log line 99999 with some padding text"));
        assert!(text.contains("error number 9999"));
        assert!(!text.contains("error number 0\n"));
    }
}
