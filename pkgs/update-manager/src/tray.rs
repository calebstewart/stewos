use std::sync::mpsc::Sender;

use crate::state::State;
use crate::{ApplyMode, Command};

pub struct UpdateTray {
    state: State,
    tx: Sender<Command>,
}

impl UpdateTray {
    pub fn new(tx: Sender<Command>) -> Self {
        Self {
            state: State::Idle,
            tx,
        }
    }

    pub fn set_state(&mut self, state: State) {
        self.state = state;
    }

    fn status_line(&self) -> String {
        match &self.state {
            State::Idle => "No check performed yet".to_string(),
            State::Checking => "Checking for updates\u{2026}".to_string(),
            State::UpToDate { checked_at } => format!("Up to date (checked {checked_at})"),
            State::UpdatesAvailable(p) => p.summary.short(),
            State::Applying => "Applying updates\u{2026}".to_string(),
            State::Error { .. } => "Error \u{2014} see tooltip".to_string(),
        }
    }

    fn busy(&self) -> bool {
        matches!(self.state, State::Checking | State::Applying)
    }
}

fn apply_item(label: &str, mode: ApplyMode) -> ksni::MenuItem<UpdateTray> {
    ksni::menu::StandardItem {
        label: label.to_string(),
        activate: Box::new(move |tray: &mut UpdateTray| {
            let _ = tray.tx.send(Command::Apply(mode));
        }),
        ..Default::default()
    }
    .into()
}

impl ksni::Tray for UpdateTray {
    fn id(&self) -> String {
        "stewos-update-manager".to_string()
    }

    fn title(&self) -> String {
        "StewOS Updates".to_string()
    }

    fn category(&self) -> ksni::Category {
        ksni::Category::SystemServices
    }

    fn icon_name(&self) -> String {
        match &self.state {
            State::Idle | State::UpToDate { .. } => "system-software-update",
            State::Checking => "emblem-synchronizing",
            State::UpdatesAvailable(_) => "software-update-available",
            State::Applying => "system-software-install",
            State::Error { .. } => "software-update-urgent",
        }
        .to_string()
    }

    fn tool_tip(&self) -> ksni::ToolTip {
        let description = match &self.state {
            State::UpdatesAvailable(p) => p.summary.breakdown(),
            State::Error { message } => message.clone(),
            _ => self.status_line(),
        };
        ksni::ToolTip {
            title: "StewOS Updates".to_string(),
            description,
            ..Default::default()
        }
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::*;

        vec![
            StandardItem {
                label: self.status_line(),
                enabled: false,
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Check for updates".to_string(),
                icon_name: "view-refresh".to_string(),
                enabled: !self.busy(),
                activate: Box::new(|tray: &mut Self| {
                    let _ = tray.tx.send(Command::Check);
                }),
                ..Default::default()
            }
            .into(),
            SubMenu {
                label: "Apply".to_string(),
                icon_name: "system-software-install".to_string(),
                enabled: matches!(self.state, State::UpdatesAvailable(_)),
                submenu: vec![
                    apply_item("System + home now", ApplyMode::Full),
                    apply_item("Home only", ApplyMode::HomeOnly),
                    apply_item("Home now, system on next boot", ApplyMode::HomeAndBoot),
                    apply_item("System only", ApplyMode::SystemOnly),
                ],
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Quit".to_string(),
                icon_name: "application-exit".to_string(),
                activate: Box::new(|tray: &mut Self| {
                    let _ = tray.tx.send(Command::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}
