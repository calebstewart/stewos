use std::sync::mpsc::Sender;
use std::sync::Arc;

use notify_rust::{Notification, Timeout, Urgency};

use crate::icons::{Icon, Icons};
use crate::{ApplyMode, Command};

const APP_NAME: &str = "StewOS Updates";

pub struct Notifier {
    tx: Sender<Command>,
    icons: Arc<Icons>,
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

    /// Persistent error notification.
    pub fn error(&self, summary: &str, body: &str) {
        let result = Self::base(&self.icons, Icon::Error, summary, body)
            .urgency(Urgency::Critical)
            .timeout(Timeout::Never)
            .show();
        if let Err(err) = result {
            log::warn!("notification failed: {err}");
        }
    }

    /// Persistent "updates available" notification with an "Apply now" action
    /// when the notification daemon supports actions. The action wait blocks,
    /// so the whole notification lives on its own short-lived thread.
    pub fn updates_available(&self, summary_line: String, breakdown: String) {
        let tx = self.tx.clone();
        let icons = self.icons.clone();
        std::thread::spawn(move || {
            let actions_supported = notify_rust::get_capabilities()
                .map(|caps| caps.iter().any(|c| c == "actions"))
                .unwrap_or(false);

            let mut n = Self::base(
                &icons,
                Icon::UpdatesAvailable,
                "Updates available",
                &format!("{summary_line}\n{breakdown}"),
            );
            n.timeout(Timeout::Never);
            if actions_supported {
                n.action("apply", "Apply now");
            }

            match n.show() {
                Ok(handle) if actions_supported => {
                    handle.wait_for_action(|action| {
                        if action == "apply" {
                            let _ = tx.send(Command::Apply(ApplyMode::Full));
                        }
                    });
                }
                Ok(_) => {}
                Err(err) => log::warn!("notification failed: {err}"),
            }
        });
    }
}
