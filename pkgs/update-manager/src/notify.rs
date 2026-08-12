use std::sync::mpsc::Sender;

use notify_rust::{Notification, Timeout, Urgency};

use crate::{ApplyMode, Command};

const APP_NAME: &str = "StewOS Updates";

pub struct Notifier {
    tx: Sender<Command>,
}

impl Notifier {
    pub fn new(tx: Sender<Command>) -> Self {
        Self { tx }
    }

    fn base(summary: &str, body: &str) -> Notification {
        let mut n = Notification::new();
        n.appname(APP_NAME)
            .summary(summary)
            .body(body)
            .icon("system-software-update");
        n
    }

    /// Transient informational notification.
    pub fn info(&self, summary: &str, body: &str) {
        let result = Self::base(summary, body)
            .timeout(Timeout::Milliseconds(5000))
            .show();
        if let Err(err) = result {
            log::warn!("notification failed: {err}");
        }
    }

    /// Persistent error notification.
    pub fn error(&self, summary: &str, body: &str) {
        let result = Self::base(summary, body)
            .icon("dialog-error")
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
        std::thread::spawn(move || {
            let actions_supported = notify_rust::get_capabilities()
                .map(|caps| caps.iter().any(|c| c == "actions"))
                .unwrap_or(false);

            let mut n = Self::base("Updates available", &format!("{summary_line}\n{breakdown}"));
            n.icon("software-update-available").timeout(Timeout::Never);
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
