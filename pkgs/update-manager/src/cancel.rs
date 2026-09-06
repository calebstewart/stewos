//! Stopping a build from another thread.
//!
//! The worker is blocked reading the child's stderr while `nix build` runs, so
//! it cannot service a "cancel" the way it services every other request. The
//! tray thread therefore signals the child directly through this handle, and
//! the worker learns about it when the pipe closes: it checks [`Canceller::
//! reason`] before it looks at the exit status, because a nix that was told to
//! stop exits non-zero and that is not a failure.
//!
//! This is deliberately not a [`crate::Command`]. A command would sit in the
//! queue behind the build it is meant to stop.

use std::process::Child;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CancelReason {
    /// The user asked, from the tray. Reported; the update stays pending.
    User,
    /// The daemon is quitting. Not reported; nothing is left to report to.
    Quit,
}

#[derive(Default)]
struct Inner {
    child: Mutex<Option<Child>>,
    /// 0 none, 1 user, 2 quit. An atomic rather than under the mutex so the
    /// worker can read it without contending with the kill thread.
    reason: AtomicU8,
}

#[derive(Clone, Default)]
pub struct Canceller(Arc<Inner>);

impl Canceller {
    /// Forget any earlier cancellation. Called by the worker at the start of
    /// each build operation, never mid-way: a cancel between the two builds
    /// of one operation must still stop the second.
    pub fn reset(&self) {
        self.0.reason.store(0, Ordering::SeqCst);
    }

    /// Hand the running child over. The caller must have taken the pipe it
    /// wants to read out of the child first; the child stays here until
    /// [`Canceller::disarm`].
    pub fn arm(&self, child: Child) {
        let mut slot = self.0.child.lock().unwrap_or_else(|e| e.into_inner());
        *slot = Some(child);
    }

    /// Take the child back to `wait()` on it, once its output has hit EOF.
    pub fn disarm(&self) -> Option<Child> {
        let mut slot = self.0.child.lock().unwrap_or_else(|e| e.into_inner());
        slot.take()
    }

    pub fn reason(&self) -> Option<CancelReason> {
        match self.0.reason.load(Ordering::SeqCst) {
            1 => Some(CancelReason::User),
            2 => Some(CancelReason::Quit),
            _ => None,
        }
    }

    /// Stop whatever is armed, and anything armed later in the same operation.
    ///
    /// SIGINT first: nix handles it by cancelling its goals through the daemon
    /// and exiting "interrupted", which also stops the builders. SIGKILL only
    /// if it has not gone away after a grace period.
    pub fn cancel(&self, reason: CancelReason) {
        let code = match reason {
            CancelReason::User => 1,
            CancelReason::Quit => 2,
        };
        self.0.reason.store(code, Ordering::SeqCst);

        let pid = {
            let slot = self.0.child.lock().unwrap_or_else(|e| e.into_inner());
            slot.as_ref().map(Child::id)
        };
        let Some(pid) = pid else {
            // Routine: every Quit passes through here, build or no build.
            log::debug!("cancel requested ({reason:?}) with no build running");
            return;
        };

        log::info!("cancelling build ({reason:?}): interrupting nix pid {pid}");
        // SAFETY: plain libc call on a pid we own; the worst case for a stale
        // pid is ESRCH, which is ignored.
        unsafe {
            libc::kill(pid as libc::pid_t, libc::SIGINT);
        }

        let inner = self.0.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(5));
            let mut slot = inner.child.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(child) = slot.as_mut() {
                if child.id() == pid {
                    log::warn!("nix pid {pid} ignored SIGINT; killing it");
                    let _ = child.kill();
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Command, Stdio};

    #[test]
    fn a_cancel_interrupts_the_armed_child() {
        let canceller = Canceller::default();
        let child = Command::new("sleep")
            .arg("30")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        canceller.arm(child);
        canceller.cancel(CancelReason::User);
        let mut child = canceller.disarm().unwrap();
        let status = child.wait().unwrap();
        assert!(!status.success());
        assert_eq!(canceller.reason(), Some(CancelReason::User));
        canceller.reset();
        assert_eq!(canceller.reason(), None);
    }

    #[test]
    fn a_cancel_with_nothing_armed_still_records_the_reason() {
        let canceller = Canceller::default();
        canceller.cancel(CancelReason::Quit);
        assert_eq!(canceller.reason(), Some(CancelReason::Quit));
        assert!(canceller.disarm().is_none());
    }
}
