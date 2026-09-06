//! Spawning the review dialog and feeding its answer back to the worker.
//!
//! Structurally this is the same shape as `notify.rs`: it owns a clone of the
//! worker's `Sender<Command>`, does its blocking work on a detached thread,
//! and sends an ordinary `Command::Apply`. The dialog therefore gains **no
//! authority the tray menu does not already have** -- `Worker::apply` and
//! `do_apply` re-check the pending state, the rev and the out-links exactly as
//! they do for a menu click.

use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command as Proc, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;

use anyhow::{Context, Result};
use stewos_update_manager::{ReviewChoice, ReviewRequest};

use crate::Command;

pub struct Reviewer {
    tx: Sender<Command>,
    dialog: PathBuf,
    /// One window at a time. A second one is confusing rather than dangerous
    /// -- its choice would hit the same guards -- but two identical windows
    /// listing the same update is not worth allowing.
    ///
    /// This clears when the child *exits*, not when it answers, so a hung
    /// dialog blocks further reviews until it is closed. That is the right way
    /// round: clearing on answer would let a second window open over the first.
    open: Arc<AtomicBool>,
}

impl Reviewer {
    pub fn new(tx: Sender<Command>, dialog: PathBuf) -> Self {
        Self {
            tx,
            dialog,
            open: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Spawn the dialog and hand the request off to a thread. Errors returned
    /// here are spawn errors only; everything after the fork is the thread's
    /// problem and is logged rather than surfaced.
    pub fn open(&self, request: &ReviewRequest) -> Result<()> {
        if self
            .open
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            log::info!("a review window is already open");
            return Ok(());
        }

        // Serialized before the spawn, so a serde failure cannot leave an
        // orphaned window with nothing to display.
        let payload = match serde_json::to_string(request) {
            Ok(payload) => payload,
            Err(err) => {
                self.open.store(false, Ordering::SeqCst);
                return Err(err).context("serializing the review request");
            }
        };

        log::info!("opening review dialog: {}", self.dialog.display());
        let child = Proc::new(&self.dialog)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            // Inherited, unlike troubleshoot::launch: the dialog is our own
            // binary, so its GTK warnings are our bug reports and belong in
            // the daemon's journal.
            .stderr(Stdio::inherit())
            .spawn();
        let mut child = match child {
            Ok(child) => child,
            Err(err) => {
                self.open.store(false, Ordering::SeqCst);
                return Err(err)
                    .with_context(|| format!("failed to run {}", self.dialog.display()));
            }
        };

        let tx = self.tx.clone();
        let open = self.open.clone();
        std::thread::spawn(move || {
            // The write happens here rather than on the worker thread on
            // purpose: a request bigger than the pipe buffer (~64 KiB, and a
            // large update gets close) would otherwise deadlock the worker
            // against a child that has not started reading yet.
            if let Some(mut stdin) = child.stdin.take() {
                if let Err(err) = stdin
                    .write_all(payload.as_bytes())
                    .and_then(|()| stdin.write_all(b"\n"))
                    .and_then(|()| stdin.flush())
                {
                    log::warn!("failed to send the review request: {err}");
                }
                // `stdin` is dropped here, closing the pipe. The dialog reads
                // exactly one line, so this is a clean end-of-request.
            }

            let mut answer = String::new();
            if let Some(mut stdout) = child.stdout.take() {
                if let Err(err) = stdout.read_to_string(&mut answer) {
                    log::warn!("failed to read the review answer: {err}");
                }
            }

            // Reaped so a session's worth of closed dialogs cannot pile up as
            // zombies, the same reason troubleshoot::launch waits on its
            // terminal.
            let status = child.wait();
            open.store(false, Ordering::SeqCst);

            match status {
                Ok(status) if !status.success() => {
                    log::warn!("review dialog exited with {status}");
                }
                Err(err) => log::warn!("waiting for the review dialog failed: {err}"),
                _ => {}
            }

            match parse_choice(&answer) {
                Some(ReviewChoice::Apply(mode)) => {
                    log::info!("review dialog chose {}", mode.describe());
                    // Ignored if the worker has already gone: shutdown races
                    // are not worth reporting.
                    let _ = tx.send(Command::Apply(mode));
                }
                Some(ReviewChoice::Build) => {
                    log::info!("review dialog chose to build");
                    let _ = tx.send(Command::Build);
                }
                Some(ReviewChoice::Dismiss) => log::info!("review dialog dismissed"),
                // Closing the window without choosing prints nothing at all.
                // That is the designed path, not an error.
                None if answer.trim().is_empty() => log::info!("review window closed"),
                None => log::warn!("unparseable review answer: {}", answer.trim()),
            }
        });
        Ok(())
    }
}

/// Read the dialog's answer: the last non-empty line, as JSON.
fn parse_choice(answer: &str) -> Option<ReviewChoice> {
    let line = answer.lines().map(str::trim).filter(|l| !l.is_empty()).last()?;
    serde_json::from_str(line).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use stewos_update_manager::{ApplyMode, Counts, Summary, PROTOCOL_VERSION};

    fn request() -> ReviewRequest {
        ReviewRequest {
            version: PROTOCOL_VERSION,
            host: "test-host".into(),
            summary: Summary {
                total: Counts::default(),
                system: Counts::default(),
                home: Counts::default(),
            },
            packages: Vec::new(),
            inputs: Vec::new(),
            modes: ApplyMode::MENU_ORDER.to_vec(),
            built: true,
            plan: None,
            roots: Vec::new(),
        }
    }

    /// Write an executable stand-in for the dialog: it echoes the request it
    /// was given to a side file, then prints `body` as its answer.
    fn fake_dialog(name: &str, body: &str) -> (PathBuf, PathBuf) {
        use std::os::unix::fs::PermissionsExt;

        let dir = std::env::temp_dir().join(format!("stewos-review-test-{name}"));
        let _ = std::fs::create_dir_all(&dir);
        let script = dir.join("dialog.sh");
        let seen = dir.join("seen.json");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\ncat > {}\n{}\n",
                seen.display(),
                if body.is_empty() {
                    ":".to_string()
                } else {
                    format!("printf '%s\\n' '{body}'")
                }
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        (script, seen)
    }

    /// The whole handshake in one test: the request reaches the child's stdin,
    /// and the child's answer comes back as an ordinary Command::Apply.
    #[test]
    fn round_trips_a_choice_through_a_real_child_process() {
        let (script, seen) = fake_dialog("apply", r#"{"apply":"home-only"}"#);
        let (tx, rx) = std::sync::mpsc::channel();
        let reviewer = Reviewer::new(tx, script);

        reviewer.open(&request()).unwrap();

        let got = rx
            .recv_timeout(std::time::Duration::from_secs(10))
            .expect("the reviewer should forward the dialog's choice");
        assert_eq!(got, Command::Apply(ApplyMode::HomeOnly));

        // And the child really was handed the request, on stdin, as one line.
        let received = std::fs::read_to_string(&seen).unwrap();
        let parsed: ReviewRequest = serde_json::from_str(received.trim()).unwrap();
        assert_eq!(parsed.host, "test-host");
    }

    /// Closing the window without choosing prints nothing. That must send no
    /// command at all rather than defaulting to something destructive.
    #[test]
    fn silence_from_the_dialog_sends_no_command() {
        let (script, _) = fake_dialog("silent", "");
        let (tx, rx) = std::sync::mpsc::channel();
        let reviewer = Reviewer::new(tx, script);

        reviewer.open(&request()).unwrap();

        assert!(rx
            .recv_timeout(std::time::Duration::from_secs(10))
            .is_err());
    }

    #[test]
    fn a_missing_dialog_is_an_error_not_a_panic() {
        let (tx, _rx) = std::sync::mpsc::channel();
        let reviewer = Reviewer::new(tx, PathBuf::from("/nonexistent/stewos-update-review"));
        assert!(reviewer.open(&request()).is_err());
        // The guard must be released, or the entry is dead for the session.
        assert!(!reviewer.open.load(Ordering::SeqCst));
    }

    #[test]
    fn reads_a_choice() {
        assert_eq!(
            parse_choice("{\"apply\":\"home-and-boot\"}\n"),
            Some(ReviewChoice::Apply(ApplyMode::HomeAndBoot))
        );
        assert_eq!(parse_choice("\"dismiss\"\n"), Some(ReviewChoice::Dismiss));
    }

    /// GTK is happy to print warnings on stdout; take the last line, not the
    /// first, so a stray line before the answer does not lose it.
    #[test]
    fn ignores_noise_before_the_answer() {
        let noisy = "Gtk-Message: something\n{\"apply\":\"full\"}\n";
        assert_eq!(
            parse_choice(noisy),
            Some(ReviewChoice::Apply(ApplyMode::Full))
        );
    }

    #[test]
    fn silence_is_not_a_choice() {
        assert_eq!(parse_choice(""), None);
        assert_eq!(parse_choice("\n  \n"), None);
        assert_eq!(parse_choice("garbage"), None);
    }
}
