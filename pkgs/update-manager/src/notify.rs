use std::sync::mpsc::Sender;
use std::sync::Arc;

use notify_rust::{Hint, Notification, NotificationHandle, Timeout, Urgency};

use crate::icons::{Icon, Icons};
use crate::state::{PendingUpdate, Progress};
use crate::troubleshoot::Action;
use crate::{ApplyMode, Command};

const APP_NAME: &str = "StewOS Updates";

pub struct Notifier {
    tx: Sender<Command>,
    icons: Arc<Icons>,
}

/// The one notification that changes in place: the build's progress bar. The
/// handle is what lets it be replaced rather than stacked, and closed when the
/// build ends so the "ready to apply" (or failure) notification that follows
/// is the only one left standing.
///
/// The `value` hint is the freedesktop convention for a progress bar (0-100),
/// which caelestia draws as a ring around the icon; the body text carries the
/// same numbers for a server that ignores it.
pub struct ProgressNotification {
    handle: NotificationHandle,
    icons: Arc<Icons>,
}

impl ProgressNotification {
    fn fill(n: &mut Notification, icons: &Icons, progress: &Progress) {
        n.body(&progress.detail())
            .icon(&icons.notify_icon(Icon::building(progress.fraction())))
            .hint(Hint::CustomInt(
                "value".to_string(),
                i32::from(progress.percent()),
            ));
    }

    pub fn update(&mut self, progress: &Progress) {
        Self::fill(&mut self.handle, &self.icons, progress);
        if let Err(err) = self.handle.update() {
            log::warn!("progress notification update failed: {err}");
        }
    }

    pub fn close(self) {
        self.handle.close();
    }
}

impl Notifier {
    pub fn new(tx: Sender<Command>, icons: Arc<Icons>) -> Self {
        Self { tx, icons }
    }

    /// Notifications draw the same art as the tray, so the two agree about what
    /// state the daemon is in. `Icons` hands back an absolute path when it has
    /// our own PNG and a theme name otherwise.
    fn base(icons: &Icons, icon: Icon, summary: &str, body: &str) -> Notification {
        let mut n = Notification::new();
        n.appname(APP_NAME)
            .summary(summary)
            .body(body)
            .icon(&icons.notify_icon(icon));
        n
    }

    /// Transient informational notification.
    pub fn info(&self, summary: &str, body: &str) {
        let result = Self::base(&self.icons, Icon::UpToDate, summary, body)
            .timeout(Timeout::Milliseconds(5000))
            .show();
        if let Err(err) = result {
            log::warn!("notification failed: {err}");
        }
    }

    /// The checkout has local changes. Transient like `info`, since the tray
    /// keeps saying so for as long as it is true, but under its own icon.
    pub fn blocked(&self, reason: &str) {
        let result = Self::base(&self.icons, Icon::Blocked, "Update blocked", reason)
            .timeout(Timeout::Milliseconds(8000))
            .show();
        if let Err(err) = result {
            log::warn!("notification failed: {err}");
        }
    }

    /// Persistent error notification, for the errors nothing can be done about
    /// from here. A failure the worker recorded a report for goes through
    /// [`Notifier::failure`] instead.
    pub fn error(&self, summary: &str, body: &str) {
        let result = Self::base(&self.icons, Icon::Error, summary, body)
            .urgency(Urgency::Critical)
            .timeout(Timeout::Never)
            .show();
        if let Err(err) = result {
            log::warn!("notification failed: {err}");
        }
    }

    /// The build's progress. Shown once; the returned handle is updated in
    /// place from then on. `None` when the server refused it, in which case
    /// the tray is the only progress display.
    pub fn progress(&self, progress: &Progress) -> Option<ProgressNotification> {
        let mut n = Self::base(
            &self.icons,
            Icon::building(progress.fraction()),
            "Building update",
            "",
        );
        n.timeout(Timeout::Never);
        ProgressNotification::fill(&mut n, &self.icons, progress);
        match n.show() {
            Ok(handle) => Some(ProgressNotification {
                handle,
                icons: self.icons.clone(),
            }),
            Err(err) => {
                log::warn!("progress notification failed: {err}");
                None
            }
        }
    }

    /// A failed check, build or apply: the same persistent error notification,
    /// plus the two entries the tray menu grows, so the report is one click
    /// away without going to the tray. Like `updates_available`, the action
    /// wait blocks, so this lives on its own thread.
    pub fn failure(&self, summary: String, body: String) {
        let tx = self.tx.clone();
        let icons = self.icons.clone();
        std::thread::spawn(move || {
            let actions_supported = notify_rust::get_capabilities()
                .map(|caps| caps.iter().any(|c| c == "actions"))
                .unwrap_or(false);

            let mut n = Self::base(&icons, Icon::Error, &summary, &body);
            n.urgency(Urgency::Critical).timeout(Timeout::Never);
            if actions_supported {
                n.action("report", "Open report");
                n.action("claude", "Troubleshoot");
            }

            match n.show() {
                Ok(handle) if actions_supported => {
                    handle.wait_for_action(|action| {
                        let action = match action {
                            "report" => Some(Action::Report),
                            "claude" => Some(Action::Claude),
                            _ => None,
                        };
                        if let Some(action) = action {
                            let _ = tx.send(Command::Troubleshoot(action));
                        }
                    });
                }
                Ok(_) => {}
                Err(err) => log::warn!("notification failed: {err}"),
            }
        });
    }

    /// The persistent "there is an update" notification, in the shape the
    /// update is in: unbuilt, with the plan and a "Build" action; or built,
    /// with the closure summary and an "Apply now" action. Either action is
    /// exactly what the tray entry of the same name sends. The action wait
    /// blocks, so the whole notification lives on its own short-lived thread.
    pub fn updates_available(&self, pending: &PendingUpdate) {
        let built = pending.built();
        let (summary, body, action_label) = if built {
            (
                "Update ready to apply",
                format!(
                    "{}\n{}",
                    pending.summary.short(),
                    pending.summary.breakdown()
                ),
                "Apply now",
            )
        } else {
            let plan = pending
                .plan
                .map(|plan| plan.describe())
                .unwrap_or_else(|| "Build plan unavailable".to_string());
            (
                "Updates available",
                format!("{}\n{plan}", pending.summary.short()),
                "Build",
            )
        };

        let tx = self.tx.clone();
        let icons = self.icons.clone();
        std::thread::spawn(move || {
            let actions_supported = notify_rust::get_capabilities()
                .map(|caps| caps.iter().any(|c| c == "actions"))
                .unwrap_or(false);

            let mut n = Self::base(&icons, Icon::UpdatesAvailable, summary, &body);
            n.timeout(Timeout::Never);
            if actions_supported {
                n.action("go", action_label);
            }

            match n.show() {
                Ok(handle) if actions_supported => {
                    handle.wait_for_action(|action| {
                        if action == "go" {
                            let command = if built {
                                Command::Apply(ApplyMode::Full)
                            } else {
                                Command::Build
                            };
                            let _ = tx.send(command);
                        }
                    });
                }
                Ok(_) => {}
                Err(err) => log::warn!("notification failed: {err}"),
            }
        });
    }
}
