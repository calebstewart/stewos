mod diff;
mod git;
mod inputs;
mod nix;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, bail, Context, Result};
use stewos_update_manager::{PackageChange, Scope};

use crate::config::Config;
use crate::notify::Notifier;
use crate::review::Reviewer;
use crate::state::{self, PendingUpdate, State, Summary};
use crate::tray::UpdateTray;
use crate::troubleshoot::{self, Action, ErrorReport, Operation};
use crate::ApplyMode;

/// Strip SGR escapes from one line of nix output. Nix colours its diffs and
/// its lock-file log, and both parsers want the text underneath.
///
/// Nix omits colour when stderr is not a tty, which it is not under
/// `Command::output()`, but a future nix could change its mind and the cost of
/// being wrong is a parser that silently matches nothing.
pub(super) fn strip_ansi(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&n) = chars.peek() {
                    chars.next();
                    if n.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

enum CheckOutcome {
    UpToDate,
    Updates(PendingUpdate),
}

/// What the privileged helper should do to the OS, if anything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SystemAction {
    None,
    Switch,
    Boot,
}

/// `ApplyMode` now lives in the shared library (the dialog needs it too), and
/// an inherent impl has to be in the defining crate -- so what is private to
/// the updater hangs off an extension trait instead. `describe()` moved to the
/// library with the type.
trait ApplyModeExt {
    fn system_action(self) -> SystemAction;
    fn includes_home(self) -> bool;
}

impl ApplyModeExt for ApplyMode {
    fn system_action(self) -> SystemAction {
        match self {
            ApplyMode::Full | ApplyMode::SystemOnly => SystemAction::Switch,
            ApplyMode::HomeAndBoot => SystemAction::Boot,
            ApplyMode::HomeOnly => SystemAction::None,
        }
    }

    fn includes_home(self) -> bool {
        !matches!(self, ApplyMode::SystemOnly)
    }
}

/// Turn one parsed diff into the wire rows the dialog renders.
fn flatten(
    diffs: &BTreeMap<String, diff::PackageDiff>,
    scope: Scope,
) -> impl Iterator<Item = PackageChange> + '_ {
    diffs.iter().map(move |(name, d)| PackageChange {
        name: name.clone(),
        change: d.change,
        before: d.before.clone(),
        after: d.after.clone(),
        size: d.size.clone(),
        scope,
    })
}

enum ApplyOutcome {
    Applied {
        os_done: bool,
        home_done: bool,
        merge_note: Option<String>,
    },
    /// The authentication dialog was declined; nothing changed.
    Cancelled,
    /// The pending update no longer matches reality; a fresh check is needed.
    Stale { message: String },
}

pub struct Worker {
    cfg: Config,
    notifier: Notifier,
    tray: ksni::Handle<UpdateTray>,
    state: State,
    /// The last failure, whichever operation it came from. Deliberately not
    /// persisted alongside `PendingUpdate`: the report quotes this boot's
    /// journal, which would not survive a restart to describe.
    last_error: Option<ErrorReport>,
    /// None when no dialog binary was found, in which case the tray also omits
    /// the Review entry.
    review: Option<Reviewer>,
}

impl Worker {
    pub fn new(
        cfg: Config,
        notifier: Notifier,
        tray: ksni::Handle<UpdateTray>,
        review: Option<Reviewer>,
    ) -> Self {
        Self {
            cfg,
            notifier,
            tray,
            state: State::Idle,
            last_error: None,
            review,
        }
    }

    /// Open the review window on the pending update.
    ///
    /// Read-only: the dialog's answer comes back as a `Command::Apply` like any
    /// other and goes through the same guards as a tray click.
    pub fn review(&self) {
        let State::UpdatesAvailable(pending) = &self.state else {
            log::info!("review requested but no update is pending");
            return;
        };
        let Some(reviewer) = &self.review else {
            log::info!("review requested but no dialog is configured");
            return;
        };
        if let Err(err) = reviewer.open(&pending.review_request(&self.cfg.host)) {
            log::error!("review dialog failed: {err:#}");
            // Plain error(), like troubleshoot(): offering to troubleshoot the
            // review window is not a useful thing to do here.
            self.notifier
                .error("Could not open the review window", &format!("{err:#}"));
        }
    }

    fn set_state(&mut self, state: State) {
        self.state = state.clone();
        self.tray.update(move |tray| tray.set_state(state.clone()));
    }

    /// Record (or clear) the failure the troubleshooting entries work from. The
    /// tray is only told whether one exists; the report stays here.
    fn set_last_error(&mut self, report: Option<ErrorReport>) {
        let has_error = report.is_some();
        self.last_error = report;
        self.tray.update(move |tray| tray.set_has_error(has_error));
    }

    /// Restore "updates available" from state.json after a restart, but only
    /// if the recorded update still matches reality.
    pub fn restore(&mut self) {
        let state_file = self.cfg.state_file();
        let Some(pending) = state::load_pending(&state_file) else {
            return;
        };
        let valid = self.pending_still_valid(&pending).unwrap_or_else(|err| {
            log::warn!("could not validate persisted state: {err:#}");
            false
        });
        if valid {
            log::info!("restored pending update from {}", state_file.display());
            self.set_state(State::UpdatesAvailable(pending));
        } else {
            log::info!("persisted state is stale, discarding");
            state::clear_pending(&state_file);
        }
    }

    fn pending_still_valid(&self, p: &PendingUpdate) -> Result<bool> {
        if git::rev_parse(&self.cfg.flake, "main")? != p.main_rev {
            return Ok(false);
        }
        let system_ok = std::fs::canonicalize(self.cfg.result_system())
            .map(|path| path == Path::new(&p.system_path))
            .unwrap_or(false);
        let home_ok = std::fs::canonicalize(self.cfg.result_home())
            .map(|path| path == Path::new(&p.home_path))
            .unwrap_or(false);
        let fully_applied =
            self.os_done(Path::new(&p.system_path)) && self.home_done(Path::new(&p.home_path));
        Ok(system_ok && home_ok && !fully_applied)
    }

    pub fn check(&mut self) {
        if matches!(self.state, State::Checking | State::Applying) {
            return;
        }
        self.set_state(State::Checking);
        self.notifier.info(
            "Checking for updates",
            "Updating flake inputs and building the new system; this can take a while.",
        );

        match self.do_check() {
            Ok(CheckOutcome::UpToDate) => {
                let checked_at = chrono::Local::now().format("%H:%M").to_string();
                self.set_last_error(None);
                self.set_state(State::UpToDate { checked_at });
                self.notifier
                    .info("Up to date", "All flake inputs are current.");
            }
            Ok(CheckOutcome::Updates(pending)) => {
                if let Err(err) = state::save_pending(&self.cfg.state_file(), &pending) {
                    log::warn!("failed to persist state: {err:#}");
                }
                self.set_last_error(None);
                self.notifier
                    .updates_available(pending.summary.short(), pending.summary.breakdown());
                self.set_state(State::UpdatesAvailable(pending));
            }
            Err(err) => {
                let message = format!("{err:#}");
                log::error!("check failed: {message}");
                self.set_last_error(Some(ErrorReport::new(Operation::Check, message.clone())));
                self.notifier
                    .failure("Update check failed".to_string(), tail(&message, 3));
                self.set_state(State::Error {
                    message: truncate(&message, 4000),
                });
            }
        }
    }

    fn do_check(&self) -> Result<CheckOutcome> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        let main_rev = git::rev_parse(flake, "main")?;
        if git::path_dirty(flake, "flake.lock")? {
            bail!(
                "flake.lock has local modifications in {}; commit or discard them first",
                flake.display()
            );
        }

        git::ensure_worktree(flake, &worktree, &self.cfg.branch)?;
        let update_log = nix::flake_update(&worktree)?;

        if !git::lock_changed(&worktree)? {
            return Ok(CheckOutcome::UpToDate);
        }

        // Parsed only past the up-to-date return, so the no-op path stays free.
        // `ensure_worktree` hard-resets onto main every check, so this log is
        // always the complete main→new diff even on a re-check.
        let input_changes = inputs::parse(&update_log);

        let system_path = nix::build(&self.cfg.system_installable(), &self.cfg.result_system())?;
        let home_path = nix::build(&self.cfg.home_installable(), &self.cfg.result_home())?;

        let system_diff = diff::parse(&nix::diff_closures(
            Path::new("/run/current-system"),
            &system_path,
        )?);
        let home_diff = match self.cfg.home_profile() {
            Some(profile) => diff::parse(&nix::diff_closures(&profile, &home_path)?),
            None => {
                log::warn!("no home-manager profile found; skipping home diff");
                BTreeMap::new()
            }
        };

        let summary = Summary {
            total: diff::counts(&diff::merge(&system_diff, &home_diff)),
            system: diff::counts(&system_diff),
            home: diff::counts(&home_diff),
        };

        // Flattened here rather than merged: the dialog groups by scope, so a
        // package touched by both closures is legitimately two rows.
        let packages = flatten(&system_diff, Scope::System)
            .chain(flatten(&home_diff, Scope::Home))
            .collect();

        Ok(CheckOutcome::Updates(PendingUpdate {
            summary,
            system_path: system_path.display().to_string(),
            home_path: home_path.display().to_string(),
            main_rev,
            packages,
            inputs: input_changes,
        }))
    }

    pub fn apply(&mut self, mode: ApplyMode) {
        let pending = match &self.state {
            State::UpdatesAvailable(p) => p.clone(),
            _ => {
                log::info!("apply requested but no update is pending");
                return;
            }
        };
        self.set_state(State::Applying);
        self.notifier.info("Applying updates", mode.describe());

        match self.do_apply(&pending, mode) {
            Ok(ApplyOutcome::Applied {
                os_done,
                home_done,
                merge_note,
            }) => {
                if os_done && home_done {
                    state::clear_pending(&self.cfg.state_file());
                    self.set_last_error(None);
                    let body = if mode == ApplyMode::HomeAndBoot {
                        format!(
                            "{}. The system generation takes effect on the next boot.",
                            pending.summary.short()
                        )
                    } else {
                        pending.summary.short()
                    };
                    match merge_note {
                        None => self.notifier.info("Update applied", &body),
                        Some(note) => self.notifier.error("Update applied with a caveat", &note),
                    }
                    self.set_state(State::Idle);
                } else {
                    // Partially applied: keep the pending update around so the
                    // remaining part can be applied later (completed parts are
                    // skipped by the idempotence guards).
                    let body = if home_done {
                        "Home was updated. The system update is still pending."
                    } else {
                        "The system was updated. The home update is still pending."
                    };
                    self.notifier.info("Update partially applied", body);
                    self.set_state(State::UpdatesAvailable(pending));
                }
            }
            Ok(ApplyOutcome::Cancelled) => {
                self.notifier.info(
                    "Apply cancelled",
                    "Authentication was declined; nothing was changed.",
                );
                self.set_state(State::UpdatesAvailable(pending));
            }
            Ok(ApplyOutcome::Stale { message }) => {
                state::clear_pending(&self.cfg.state_file());
                self.notifier.error("Update no longer applies", &message);
                self.set_state(State::Idle);
            }
            Err(err) => {
                // Retryable: the idempotence guards skip whatever already
                // succeeded on the next attempt.
                let message = format!("{err:#}");
                log::error!("apply failed: {message}");
                self.set_last_error(Some(ErrorReport::new(
                    Operation::Apply(mode),
                    message.clone(),
                )));
                self.notifier
                    .failure("Apply failed".to_string(), tail(&message, 3));
                self.set_state(State::UpdatesAvailable(pending));
            }
        }
    }

    /// Write a report about the last failure and open it. Both entry points --
    /// the tray menu and the error notification's buttons -- land here, so the
    /// report has exactly one writer.
    pub fn troubleshoot(&mut self, action: Action) {
        let Some(report) = &self.last_error else {
            log::info!("troubleshoot requested but no failure is recorded");
            return;
        };

        let result = troubleshoot::write(&self.cfg, report)
            .and_then(|path| troubleshoot::launch(&self.cfg, action, &path));
        if let Err(err) = result {
            log::error!("troubleshoot failed: {err:#}");
            // Plain error(): offering to troubleshoot the troubleshooter is
            // not a useful thing to do here.
            self.notifier
                .error("Could not open the failure report", &format!("{err:#}"));
        }
    }

    fn do_apply(&self, p: &PendingUpdate, mode: ApplyMode) -> Result<ApplyOutcome> {
        let flake = &self.cfg.flake;

        if git::rev_parse(flake, "main")? != p.main_rev {
            return Ok(ApplyOutcome::Stale {
                message: "main moved since the last check; run Check for updates again."
                    .to_string(),
            });
        }
        if git::path_dirty(flake, "flake.lock")? {
            bail!(
                "flake.lock has local modifications in {}; commit or discard them first",
                flake.display()
            );
        }

        let system_path = PathBuf::from(&p.system_path);
        let home_path = PathBuf::from(&p.home_path);
        let results_ok = std::fs::canonicalize(self.cfg.result_system())
            .map(|path| path == system_path)
            .unwrap_or(false)
            && std::fs::canonicalize(self.cfg.result_home())
                .map(|path| path == home_path)
                .unwrap_or(false);
        if !results_ok {
            return Ok(ApplyOutcome::Stale {
                message: "The built update is gone; run Check for updates again.".to_string(),
            });
        }

        let mut os_done = self.os_done(&system_path);
        let mut home_done = self.home_done(&home_path);

        // The OS part first: run0 escalates through polkit, so the
        // authentication dialog comes from the session's agent and no setuid
        // binary is involved. `switch` activates now; `boot` only sets the
        // profile and boot entry. Both are skipped when already done.
        match mode.system_action() {
            SystemAction::Switch
                if std::fs::canonicalize("/run/current-system")
                    .context("resolving /run/current-system")?
                    != system_path =>
            {
                match self.run_system_helper("switch", &p.system_path)? {
                    true => os_done = true,
                    false => return Ok(ApplyOutcome::Cancelled),
                }
            }
            SystemAction::Boot if !os_done => {
                match self.run_system_helper("boot", &p.system_path)? {
                    true => os_done = true,
                    false => return Ok(ApplyOutcome::Cancelled),
                }
            }
            SystemAction::None => {}
            _ => log::info!("system part already applied, skipping"),
        }

        // Merge the lock bump back into main as soon as both parts are done
        // or about to be — and *before* home activation, because the new home
        // generation contains a new daemon binary, so activating it can
        // restart this very service, and the merge must not be lost.
        let mut merge_note = None;
        if os_done && (home_done || mode.includes_home()) {
            merge_note = self.merge_back(&p.main_rev).err().map(|err| {
                format!(
                    "The update was applied, but flake.lock could not be fast-forwarded into \
                     main ({err:#}). Merge branch '{}' manually.",
                    self.cfg.branch
                )
            });
        }

        // The home part, unprivileged, skipped if the profile already points
        // at the new generation.
        if mode.includes_home() && !home_done {
            log::info!("activating home generation: {}", p.home_path);
            let output = Command::new(home_path.join("activate"))
                .output()
                .context("failed to run home activation")?;
            if !output.status.success() {
                bail!(
                    "home activation failed (retry an apply that includes home; completed \
                     parts are skipped):\n{}",
                    String::from_utf8_lossy(&output.stderr).trim()
                );
            }
            home_done = true;
        }

        Ok(ApplyOutcome::Applied {
            os_done,
            home_done,
            merge_note,
        })
    }

    /// Has the OS part been applied? True when the system profile (which both
    /// `switch` and `boot` set) or the running system points at the new
    /// generation.
    fn os_done(&self, system_path: &Path) -> bool {
        let profile = std::fs::canonicalize("/nix/var/nix/profiles/system")
            .map(|path| path == system_path)
            .unwrap_or(false);
        let running = std::fs::canonicalize("/run/current-system")
            .map(|path| path == system_path)
            .unwrap_or(false);
        profile || running
    }

    fn home_done(&self, home_path: &Path) -> bool {
        self.cfg
            .home_profile()
            .and_then(|profile| std::fs::canonicalize(profile).ok())
            .as_deref()
            == Some(home_path)
    }

    /// Run the privileged helper via run0. Returns Ok(false) when the
    /// authentication dialog was declined.
    fn run_system_helper(&self, action: &str, system_path: &str) -> Result<bool> {
        let helper = apply_helper()?;
        log::info!("running system {action} via run0: {system_path}");
        let output = Command::new("run0")
            .arg("--pipe")
            .arg(helper)
            .arg(action)
            .arg(system_path)
            .output()
            .context("failed to run run0")?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if auth_declined(&stderr) {
                log::warn!("run0 authentication declined: {}", stderr.trim());
                return Ok(false);
            }
            bail!("system {action} failed:\n{}", stderr.trim());
        }
        Ok(true)
    }

    fn merge_back(&self, main_rev: &str) -> Result<()> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        if git::lock_changed(&worktree)? {
            git::commit_lock(&worktree)?;
        }
        // Already merged by an earlier, partially completed apply.
        if git::rev_parse(flake, "main")? == git::rev_parse(flake, &self.cfg.branch)? {
            return Ok(());
        }
        if git::path_dirty(flake, "flake.lock")? {
            bail!("flake.lock was modified locally during the apply");
        }
        if git::rev_parse(flake, "main")? != main_rev {
            bail!("main moved during the apply");
        }
        git::merge_back(flake, &self.cfg.branch)
    }
}

/// Did run0 fail because authorization was declined or the dialog dismissed,
/// rather than because the switch itself failed?
fn auth_declined(stderr: &str) -> bool {
    let s = stderr.to_lowercase();
    s.contains("access denied") || s.contains("authentication") || s.contains("not authorized")
}

fn apply_helper() -> Result<PathBuf> {
    if let Ok(helper) = std::env::var("STEWOS_APPLY_HELPER") {
        return Ok(PathBuf::from(helper));
    }
    let exe = std::env::current_exe().context("resolving own executable path")?;
    exe.parent()
        .and_then(Path::parent)
        .map(|prefix| prefix.join("libexec/stewos-apply-system"))
        .filter(|helper| helper.exists())
        .ok_or_else(|| {
            anyhow!("stewos-apply-system helper not found; set STEWOS_APPLY_HELPER for dev runs")
        })
}

/// Last `lines` lines of a message, for notification bodies.
fn tail(message: &str, lines: usize) -> String {
    let all: Vec<&str> = message.lines().collect();
    let start = all.len().saturating_sub(lines);
    all[start..].join("\n")
}

fn truncate(message: &str, max: usize) -> String {
    if message.len() <= max {
        message.to_string()
    } else {
        let mut end = max;
        while !message.is_char_boundary(end) {
            end -= 1;
        }
        format!("{}\u{2026}", &message[..end])
    }
}
