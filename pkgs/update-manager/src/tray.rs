use std::sync::mpsc::Sender;
use std::sync::Arc;

use crate::icons::{Icon, Icons, MenuIcon};
use crate::state::State;
use crate::troubleshoot::Action;
use crate::{ApplyMode, Command};

pub struct UpdateTray {
    state: State,
    tx: Sender<Command>,
    icons: Arc<Icons>,
    /// Whether the worker is holding a failure worth reporting on. The report
    /// itself stays with the worker; the menu only needs to know it exists.
    has_error: bool,
    /// False when no terminal is configured, in which case the troubleshooting
    /// entries have nothing to open and are never shown.
    troubleshoot_available: bool,
}

impl UpdateTray {
    pub fn new(tx: Sender<Command>, icons: Arc<Icons>, troubleshoot_available: bool) -> Self {
        Self {
            state: State::Idle,
            tx,
            icons,
            has_error: false,
            troubleshoot_available,
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

    pub fn set_has_error(&mut self, has_error: bool) {
        self.has_error = has_error;
    }

    /// A recorded failure takes the menu over from a pending update: the two
    /// blocks are mutually exclusive, and the failure is the thing to deal
    /// with first.
    fn troubleshootable(&self) -> bool {
        self.has_error && self.troubleshoot_available
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

fn troubleshoot_item(
    tray: &UpdateTray,
    label: &str,
    icon: MenuIcon,
    action: Action,
) -> ksni::MenuItem<UpdateTray> {
    ksni::menu::StandardItem {
        label: label.to_string(),
        icon_name: tray.icons.menu_name(icon),
        icon_data: tray.icons.menu_data(icon),
        // The worker runs everything on one thread, so a click during a check
        // would sit in the queue for as long as the build takes.
        enabled: !tray.busy(),
        activate: Box::new(move |tray: &mut UpdateTray| {
            let _ = tray.tx.send(Command::Troubleshoot(action));
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

    /// Contextual: between "Check for updates" and "Quit" there is at most one
    /// block, and only when there is something to act on. A recorded failure
    /// wins over a pending update, so a failed apply trades its retry entry for
    /// the troubleshooting ones until the next successful check.
    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::*;

        let mut items: Vec<ksni::MenuItem<Self>> = vec![
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
        ];

        if self.troubleshootable() {
            items.push(troubleshoot_item(
                self,
                "Open failure report",
                MenuIcon::Report,
                Action::Report,
            ));
            items.push(troubleshoot_item(
                self,
                "Troubleshoot with Claude",
                MenuIcon::Troubleshoot,
                Action::Claude,
            ));
        } else if matches!(self.state, State::UpdatesAvailable(_)) {
            items.push(
                SubMenu {
                    label: "Apply".to_string(),
                    icon_name: self.icons.menu_name(MenuIcon::Apply),
                    icon_data: self.icons.menu_data(MenuIcon::Apply),
                    submenu: vec![
                        apply_item("System + home now", ApplyMode::Full),
                        apply_item("Home only", ApplyMode::HomeOnly),
                        apply_item("Home now, system on next boot", ApplyMode::HomeAndBoot),
                        apply_item("System only", ApplyMode::SystemOnly),
                    ],
                    ..Default::default()
                }
                .into(),
            );
        }

        items.push(MenuItem::Separator);
        items.push(
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
        );
        items
    }
}
