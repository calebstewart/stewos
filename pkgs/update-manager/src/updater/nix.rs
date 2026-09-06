use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use stewos_update_manager::BuildPlan;

use super::plan;
use super::progress::{self, Tracker};
use super::roots::{self, Root};
use crate::cancel::{CancelReason, Canceller};

/// Both of nix's streams. Most callers want stdout; `flake_update` wants
/// stderr, because nix prints the lock-file diff through its warning logger.
pub struct NixOutput {
    pub stdout: String,
    pub stderr: String,
}

/// The program to run. Overridable so a test can substitute a script that
/// prints a canned log stream.
fn program() -> String {
    std::env::var("STEWOS_NIX").unwrap_or_else(|_| "nix".to_string())
}

fn command(args: &[&str]) -> Command {
    let mut cmd = Command::new(program());
    cmd.args(["--extra-experimental-features", "nix-command flakes"])
        .args(args);
    cmd
}

/// Run nix with the given arguments. Build logs go to stderr, which is
/// captured and included in errors (and our journal).
fn nix(args: &[&str]) -> Result<NixOutput> {
    log::info!("running: nix {}", args.join(" "));
    let output = command(args)
        .output()
        .with_context(|| format!("failed to run nix {}", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "nix {} failed:\n{}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(NixOutput {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

/// Update the worktree's lock file, returning the log nix printed while doing
/// it. That log is the only record of *which inputs moved*, and it arrives on
/// **stderr** -- stdout is empty here.
pub fn flake_update(worktree: &Path) -> Result<String> {
    let wt = worktree.to_string_lossy();
    Ok(nix(&["flake", "update", "--flake", &wt])?.stderr)
}

/// What building these would fetch and build, without doing either. One call
/// for all installables so shared dependencies are counted once.
pub fn dry_run(installables: &[&str]) -> Result<BuildPlan> {
    let mut args = vec!["build", "--dry-run", "--no-link"];
    args.extend(installables);
    Ok(plan::parse(&nix(&args)?.stderr))
}

/// The names and versions of a package list, from evaluation alone.
pub fn eval_roots(installable: &str) -> Result<Vec<Root>> {
    roots::parse(&nix(&["eval", "--json", installable, "--apply", roots::APPLY])?.stdout)
}

pub enum BuildOutcome {
    Built(PathBuf),
    Cancelled(CancelReason),
}

/// Build an installable with a GC-rooted out-link, streaming nix's progress
/// into `tracker` and calling `on_event` after every record, and return the
/// store path.
///
/// Only stderr is piped, and it is read to EOF before the child is waited
/// on -- a build log easily exceeds the pipe buffer. Lines are read as bytes
/// and converted lossily: build logs are not guaranteed to be UTF-8, and
/// `lines()` would abort the whole read on the first bad byte.
pub fn build_streaming(
    installable: &str,
    out_link: &Path,
    canceller: &Canceller,
    tracker: &mut Tracker,
    mut on_event: impl FnMut(&Tracker),
) -> Result<BuildOutcome> {
    let link = out_link.to_string_lossy();
    let args = [
        "build",
        installable,
        "--out-link",
        &link,
        "--log-format",
        "internal-json",
    ];
    log::info!("running: nix {}", args.join(" "));
    let mut child = command(&args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to run nix build {installable}"))?;
    // Taken before the child is handed over: the canceller owns the child,
    // this function owns the pipe.
    let stderr = child.stderr.take().context("nix stderr was not piped")?;
    canceller.arm(child);

    let mut reader = BufReader::new(stderr);
    let mut buf = Vec::new();
    loop {
        buf.clear();
        let n = reader
            .read_until(b'\n', &mut buf)
            .context("reading nix's output")?;
        if n == 0 {
            break;
        }
        let line = String::from_utf8_lossy(&buf);
        let line = line.trim_end_matches(['\n', '\r']);
        match progress::parse_line(line) {
            Some(event) => {
                tracker.apply(&event);
                on_event(tracker);
            }
            None => tracker.note_raw(line),
        }
    }

    let status = match canceller.disarm() {
        Some(mut child) => child.wait().context("waiting for nix")?,
        None => bail!("the nix build process went missing"),
    };
    // Before the exit status: an interrupted nix exits non-zero, and that is
    // not a failure.
    if let Some(reason) = canceller.reason() {
        return Ok(BuildOutcome::Cancelled(reason));
    }
    if !status.success() {
        bail!(
            "nix build {installable} failed:\n{}",
            tracker.failure_text()
        );
    }
    let path = std::fs::canonicalize(out_link)
        .with_context(|| format!("resolving out-link {}", out_link.display()))?;
    Ok(BuildOutcome::Built(path))
}

pub fn diff_closures(old: &Path, new: &Path) -> Result<String> {
    let (old, new) = (old.to_string_lossy(), new.to_string_lossy());
    Ok(nix(&["store", "diff-closures", &old, &new])?.stdout)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{Duration, Instant};

    /// A stand-in nix: prints a canned record stream, then either exits or
    /// sleeps so a cancel has something to interrupt.
    fn fake_nix(name: &str, script: &str) -> PathBuf {
        let dir = std::env::temp_dir().join("stewos-update-manager-nix-test");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(name);
        std::fs::write(&path, format!("#!/bin/sh\n{script}")).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    /// The env var is process-global, so the two tests that set it must not
    /// run at once.
    static ENV: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn streams_events_and_resolves_the_out_link() {
        let _guard = ENV.lock().unwrap_or_else(|e| e.into_inner());
        let dir = std::env::temp_dir().join("stewos-update-manager-nix-test-ok");
        std::fs::create_dir_all(&dir).unwrap();
        let target = dir.join("target");
        std::fs::write(&target, "").unwrap();
        let link = dir.join("result");
        let _ = std::fs::remove_file(&link);
        let script = format!(
            "out=''\nwhile [ $# -gt 0 ]; do [ \"$1\" = --out-link ] && out=$2; shift; done\n\
             echo '@nix {{\"action\":\"start\",\"id\":1,\"type\":103,\"text\":\"\"}}' >&2\n\
             echo '@nix {{\"action\":\"result\",\"id\":1,\"type\":105,\"fields\":[2,2,0,0]}}' >&2\n\
             echo 'not a record' >&2\n\
             ln -sfn {} \"$out\"\n",
            target.display()
        );
        let nix = fake_nix("nix-ok", &script);
        std::env::set_var("STEWOS_NIX", &nix);

        let canceller = Canceller::default();
        let mut tracker = Tracker::new();
        let mut events = 0;
        let outcome =
            build_streaming("x", &link, &canceller, &mut tracker, |_| events += 1).unwrap();
        std::env::remove_var("STEWOS_NIX");

        assert_eq!(events, 2);
        match outcome {
            BuildOutcome::Built(path) => {
                assert_eq!(path, std::fs::canonicalize(&target).unwrap())
            }
            BuildOutcome::Cancelled(_) => panic!("not cancelled"),
        }
        assert_eq!(tracker.snapshot(&BuildPlan::default()).paths_done, 2);
        assert!(tracker.failure_text().contains("not a record"));
    }

    #[test]
    fn a_cancel_while_nix_runs_is_reported_as_such() {
        let _guard = ENV.lock().unwrap_or_else(|e| e.into_inner());
        let nix = fake_nix(
            "nix-slow",
            "echo '@nix {\"action\":\"msg\",\"level\":0,\"msg\":\"still going\"}' >&2\nexec sleep 30\n",
        );
        std::env::set_var("STEWOS_NIX", &nix);

        let canceller = Canceller::default();
        let started = Instant::now();
        let mut tracker = Tracker::new();
        let link = std::env::temp_dir().join("stewos-update-manager-nix-test-cancel-link");
        let c = canceller.clone();
        let outcome = build_streaming("x", &link, &canceller, &mut tracker, move |_| {
            c.cancel(CancelReason::User);
        })
        .unwrap();
        std::env::remove_var("STEWOS_NIX");

        assert!(matches!(
            outcome,
            BuildOutcome::Cancelled(CancelReason::User)
        ));
        assert!(started.elapsed() < Duration::from_secs(20));
    }
}
