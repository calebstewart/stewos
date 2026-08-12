use std::sync::mpsc::Sender;
use std::sync::Arc;

use crate::icons::{Icon, Icons, MenuIcon};
use crate::state::State;
use crate::{ApplyMode, Command};

pub struct UpdateTray {
    state: State,
    tx: Sender<Command>,
    icons: Arc<Icons>,
}

impl UpdateTray {
    pub fn new(tx: Sender<Command>, icons: Arc<Icons>) -> Self {
        Self {
            state: State::Idle,
            tx,
            icons,
        }
    }

    fn icon(&self) -> Icon {
        match &self.state {
            State::Idle => Icon::Idle,
            State::Checking => Icon::Checking,
            State::UpToDate { .. } => Icon::UpToDate,
            State::UpdatesAvailable(_) => Icon::UpdatesAvailable,
            State::Applying => Icon::Applying,
            State::Error { .. } => Icon::Error,
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

    // Our own art goes out as a pixmap so the glyph does not depend on the
    // host's icon theme; the name is left empty in that case, because a host
    // that can resolve IconName will prefer it over IconPixmap.
    fn icon_name(&self) -> String {
        self.icons.name(self.icon())
    }

    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        self.icons.pixmaps(self.icon())
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
                icon_name: self.icons.menu_name(MenuIcon::Search),
                icon_data: self.icons.menu_data(MenuIcon::Search),
                enabled: !self.busy(),
                activate: Box::new(|tray: &mut Self| {
                    let _ = tray.tx.send(Command::Check);
                }),
                ..Default::default()
            }
            .into(),
            SubMenu {
                label: "Apply".to_string(),
                icon_name: self.icons.menu_name(MenuIcon::Apply),
                icon_data: self.icons.menu_data(MenuIcon::Apply),
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
                icon_name: self.icons.menu_name(MenuIcon::Quit),
                icon_data: self.icons.menu_data(MenuIcon::Quit),
                activate: Box::new(|tray: &mut Self| {
                    let _ = tray.tx.send(Command::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}
