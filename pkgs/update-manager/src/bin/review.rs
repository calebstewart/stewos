//! The update-manager review dialog.
//!
//! A short-lived GTK4/libadwaita window the daemon spawns. It reads one line of
//! JSON ([`ReviewRequest`]) on stdin and prints one line of JSON
//! ([`ReviewChoice`]) on stdout, or nothing at all if the window is closed
//! without a choice.
//!
//! It is a separate process from the daemon on purpose: the tray keeps its tiny
//! footprint, GTK is only resident while the window is up, and a crash here
//! cannot take the tray down. It renders only what the daemon computed and
//! derives nothing, so the two can never disagree about what is pending.

use std::io::{BufRead, Write};

use gtk4 as gtk;
use libadwaita as adw;

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use stewos_update_manager::{
    ApplyMode, Change, InputChange, InputKind, PackageChange, ReviewChoice, ReviewRequest, Scope,
    PROTOCOL_VERSION,
};

const APP_ID: &str = "dev.stewos.UpdateReview";

/// Nix's "present but carries no version", as opposed to absent.
const UNVERSIONED: &str = "\u{3b5}";

const CSS: &str = "
.change-size { font-size: 0.85em; opacity: 0.55; }
.kind-badge {
  font-size: 0.75em; font-weight: bold;
  padding: 1px 7px; border-radius: 6px;
  min-width: 62px;
}
.kind-added    { background: alpha(@success_color, .18); color: @success_color; }
.kind-removed  { background: alpha(@error_color, .18);   color: @error_color; }
.kind-rebuilt  { background: alpha(@window_fg_color, .10); opacity: .7; }
.kind-upgraded { background: alpha(@accent_color, .18);  color: @accent_color; }
.section-counts {
  font-family: monospace; font-size: 0.95em;
  margin-right: 6px;
}
/* Each figure takes the colour of the badge its rows carry, so a glance at a
   collapsed section says the same thing as opening it. */
.count-upgraded { color: @accent_color; }
.count-added    { color: @success_color; }
.count-removed  { color: @error_color; }
/* A zero is not news: mute it so only the non-zero figures carry colour. */
.count-zero     { color: @window_fg_color; opacity: 0.35; }
";

fn main() -> glib::ExitCode {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let request = match read_request() {
        Ok(request) => request,
        Err(err) => {
            eprintln!("stewos-update-review: {err:#}");
            return glib::ExitCode::FAILURE;
        }
    };

    let app = adw::Application::builder()
        .application_id(APP_ID)
        // The daemon may open this more than once in a session, and each is its
        // own process; without this the second would hand off to the first and
        // exit immediately, printing nothing.
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();

    app.connect_startup(|_| {
        let provider = gtk::CssProvider::new();
        provider.load_from_string(CSS);
        if let Some(display) = gdk::Display::default() {
            gtk::style_context_add_provider_for_display(
                &display,
                &provider,
                gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
    });

    app.connect_activate(move |app| build(app, &request));
    app.run_with_args::<&str>(&[])
}

/// Read the one line of JSON the daemon writes to our stdin.
fn read_request() -> anyhow::Result<ReviewRequest> {
    use anyhow::{bail, Context};

    let mut line = String::new();
    std::io::stdin()
        .lock()
        .read_line(&mut line)
        .context("reading the review request from stdin")?;
    if line.trim().is_empty() {
        bail!("no review request on stdin");
    }

    let request: ReviewRequest =
        serde_json::from_str(line.trim()).context("parsing the review request")?;
    // A home activation can leave an old daemon running against a new dialog
    // until the unit restarts. Fail loudly rather than misrender.
    if request.version != PROTOCOL_VERSION {
        bail!(
            "review protocol mismatch: daemon sent v{}, this dialog speaks v{}. \
             Restart stewos-update-manager.",
            request.version,
            PROTOCOL_VERSION
        );
    }
    Ok(request)
}

/// A parent that exists only to make this window a *dialog*.
///
/// Wayland has no `_NET_WM_WINDOW_TYPE_DIALOG`; the only signal is
/// `xdg_toplevel.set_parent()`, and GTK emits it only for a parent that has
/// actually been mapped. So we map one that cannot be seen: 1x1 and
/// non-resizable, so a tiling compositor floats it rather than tiling it, and
/// fully transparent and undecorated, so there is nothing to draw. It stays
/// mapped for the dialog's lifetime, which is what avoids the visible flash
/// every hide-it-afterwards variant has.
///
/// Measured on Hyprland: without this the window is tiled full-height and the
/// requested size is ignored; `set_modal(true)` alone does nothing, and hiding
/// the parent before presenting the child does not float it either.
fn ghost_parent(app: &adw::Application) -> adw::ApplicationWindow {
    let parent = adw::ApplicationWindow::builder()
        .application(app)
        .title("")
        .default_width(1)
        .default_height(1)
        .resizable(false)
        .decorated(false)
        .opacity(0.0)
        .build();
    parent.present();
    parent
}

fn build(app: &adw::Application, request: &ReviewRequest) {
    let parent = ghost_parent(app);

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Pending changes")
        .default_width(720)
        // Height follows the content; see the scroller below.
        .modal(true)
        .transient_for(&parent)
        .build();

    let view = adw::ToolbarView::new();
    view.add_top_bar(&{
        let header = adw::HeaderBar::new();
        header.set_title_widget(Some(
            &adw::WindowTitle::builder()
                .title("Pending changes")
                .subtitle(request.summary.short())
                .build(),
        ));
        header
    });

    let group = adw::PreferencesGroup::new();
    let mut sections = Vec::new();

    // Only inputs this flake declares; transitive ones are a count, not rows.
    let top: Vec<&InputChange> = request.inputs.iter().filter(|i| i.is_top_level()).collect();
    let transitive = request.inputs.len() - top.len();
    if !top.is_empty() {
        let mut note = format!("{} moved", top.len());
        if transitive > 0 {
            note.push_str(&format!(", {transitive} transitive"));
        }
        let section = make_section("Flake inputs", &note_label(&note));
        for input in &top {
            section.add_row(&input_row(input));
        }
        group.add(&section);
        sections.push((section, true));
    }

    for (title, scope) in [("System", Scope::System), ("Home", Scope::Home)] {
        let rows: Vec<&PackageChange> = request
            .packages
            .iter()
            .filter(|p| p.scope == scope)
            .collect();
        if rows.is_empty() {
            continue;
        }
        let counts = match scope {
            Scope::System => request.summary.system,
            Scope::Home => request.summary.home,
        };
        let section = make_section(title, &tally(counts));
        for package in &rows {
            section.add_row(&package_row(package));
        }
        group.add(&section);
        sections.push((section, false));
    }

    // Applied only once every section is in the group: adding an ExpanderRow to
    // an AdwPreferencesGroup resets its expansion, so setting it at build time
    // silently does nothing.
    for (section, expanded) in &sections {
        section.set_expanded(*expanded);
    }

    // Not an AdwPreferencesPage: that clamps content near 600px and centres it,
    // so the window reads as wider than what is in it. These rows carry long
    // version strings, so the clamp is ours and much wider.
    let clamp = adw::Clamp::builder()
        .maximum_size(1100)
        .tightening_threshold(900)
        .margin_top(12)
        .margin_bottom(12)
        .margin_start(12)
        .margin_end(12)
        .child(&group)
        .build();

    // No vexpand: it would force the scroller to fill the window and defeat
    // propagate_natural_height, leaving dead space under the list.
    let scroller = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .propagate_natural_height(true)
        .max_content_height(620)
        .child(&clamp)
        .build();
    view.set_content(Some(&scroller));

    view.add_bottom_bar(&footer(request, &window, &parent));
    window.set_content(Some(&view));

    // Closing the window without choosing prints nothing, which the daemon
    // reads as "dismissed". The ghost parent must go too, or the application
    // never exits.
    let ghost = parent.clone();
    window.connect_close_request(move |_| {
        ghost.close();
        glib::Propagation::Proceed
    });

    window.present();
}

/// A collapsible section whose totals sit at the right of its heading.
///
/// `AdwExpanderRow` gives both: the title is the heading, `add_suffix` anchors
/// a widget to the right of it (before the chevron), and the rows live behind
/// the disclosure. The title is Pango markup rather than a CSS selector into
/// the row's internal box hierarchy, which is not stable API.
fn make_section(title: &str, tally: &impl IsA<gtk::Widget>) -> adw::ExpanderRow {
    let row = adw::ExpanderRow::builder()
        .title(format!("<b>{}</b>", glib::markup_escape_text(title)))
        .build();
    row.add_suffix(tally);
    row
}

/// The `12↑ 3+ 1−` tally, one label per figure so each can take its own
/// colour.
///
/// Three labels rather than one with Pango markup: the colours are theme
/// variables (`@accent_color` and friends, which `theme.nix` generates from the
/// palette), and Pango markup only understands literal colours.
fn tally(counts: stewos_update_manager::Counts) -> gtk::Box {
    let row = gtk::Box::builder()
        .orientation(gtk::Orientation::Horizontal)
        .spacing(8)
        .valign(gtk::Align::Center)
        .build();
    for (value, suffix, class) in [
        (counts.upgraded, '\u{2191}', "count-upgraded"),
        (counts.added, '+', "count-added"),
        (counts.removed, '\u{2212}', "count-removed"),
    ] {
        let label = gtk::Label::new(Some(&format!("{value}{suffix}")));
        label.add_css_class("section-counts");
        label.add_css_class(if value == 0 { "count-zero" } else { class });
        row.append(&label);
    }
    row
}

/// The same idea for the inputs heading, which counts differently.
fn note_label(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.add_css_class("section-counts");
    label.add_css_class("count-upgraded");
    label.set_valign(gtk::Align::Center);
    label
}

fn badge(label: &str, class: &str) -> gtk::Label {
    let badge = gtk::Label::new(Some(label));
    badge.add_css_class("kind-badge");
    badge.add_css_class(class);
    badge.set_valign(gtk::Align::Center);
    badge
}

/// Render a version list, turning nix's `ε` into something readable.
fn versions(list: &[String]) -> String {
    if list.is_empty() {
        return "\u{2014}".to_string();
    }
    list.iter()
        .map(|v| {
            if v == UNVERSIONED {
                "unversioned"
            } else {
                v.as_str()
            }
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn package_row(package: &PackageChange) -> adw::ActionRow {
    // A rebuild has no versions on either side; say so rather than drawing an
    // arrow between two dashes.
    let (label, class, subtitle) = if package.is_rebuild() {
        ("rebuilt", "kind-rebuilt", "same version, rebuilt".to_string())
    } else {
        match package.change {
            Change::Added => ("new", "kind-added", versions(&package.after)),
            Change::Removed => (
                "removed",
                "kind-removed",
                format!("was {}", versions(&package.before)),
            ),
            Change::Upgraded => (
                "upgrade",
                "kind-upgraded",
                format!(
                    "{}  \u{2192}  {}",
                    versions(&package.before),
                    versions(&package.after)
                ),
            ),
        }
    };

    let row = adw::ActionRow::builder()
        .title(glib::markup_escape_text(&package.name))
        .subtitle(glib::markup_escape_text(&subtitle))
        .build();
    row.add_prefix(&badge(label, class));

    // The size delta is the only thing a rebuild row has to show, which is why
    // it is here at all.
    if let Some(size) = &package.size {
        let label = gtk::Label::new(Some(size));
        label.add_css_class("change-size");
        label.set_valign(gtk::Align::Center);
        row.add_suffix(&label);
    }
    row
}

fn input_row(input: &InputChange) -> adw::ActionRow {
    let short = |r: &Option<String>| {
        r.as_deref()
            .map(InputChange::short)
            .unwrap_or_else(|| "\u{2014}".to_string())
    };
    let (label, class, subtitle) = match input.kind {
        InputKind::Added => ("new", "kind-added", short(&input.after)),
        InputKind::Removed => ("removed", "kind-removed", format!("was {}", short(&input.before))),
        InputKind::Updated => (
            "bumped",
            "kind-upgraded",
            format!("{}  \u{2192}  {}", short(&input.before), short(&input.after)),
        ),
    };

    let row = adw::ActionRow::builder()
        .title(glib::markup_escape_text(&input.name))
        .subtitle(glib::markup_escape_text(&subtitle))
        .build();
    row.add_prefix(&badge(label, class));
    row
}

/// Cancel plus an Apply split button whose menu picks the mode.
///
/// The menu is driven by a *stateful* action, so libadwaita renders the radio
/// tick against the current selection and the button label stays in sync for
/// free. Picking from the menu re-arms the button but does not apply: Apply
/// stays a deliberate second click.
fn footer(
    request: &ReviewRequest,
    window: &adw::ApplicationWindow,
    parent: &adw::ApplicationWindow,
) -> gtk::Box {
    let bar = gtk::Box::builder()
        .orientation(gtk::Orientation::Horizontal)
        .spacing(6)
        .margin_top(10)
        .margin_bottom(10)
        .margin_start(12)
        .margin_end(12)
        .build();

    bar.append(&gtk::Box::builder().hexpand(true).build());

    let cancel = gtk::Button::with_label("Cancel");
    {
        let window = window.clone();
        cancel.connect_clicked(move |_| window.close());
    }
    bar.append(&cancel);

    // The daemon decides which modes exist; fall back so the dialog is never
    // unusable if it sends an empty list.
    let modes: Vec<ApplyMode> = if request.modes.is_empty() {
        ApplyMode::MENU_ORDER.to_vec()
    } else {
        request.modes.clone()
    };
    let default = modes[0];

    let action = gio::SimpleAction::new_stateful(
        "mode",
        Some(glib::VariantTy::STRING),
        &mode_id(default).to_variant(),
    );
    let actions = gio::SimpleActionGroup::new();
    actions.add_action(&action);
    window.insert_action_group("review", Some(&actions));

    let menu = gio::Menu::new();
    for mode in &modes {
        menu.append(
            Some(mode.menu_label()),
            Some(&format!("review.mode::{}", mode_id(*mode))),
        );
    }

    let apply = adw::SplitButton::builder()
        .label(format!("Apply: {}", default.menu_label()))
        .menu_model(&menu)
        .build();
    apply.add_css_class("suggested-action");

    {
        let apply = apply.clone();
        let modes = modes.clone();
        action.connect_change_state(move |action, value| {
            let Some(value) = value else { return };
            action.set_state(value);
            if let Some(mode) = value.str().and_then(|id| mode_from_id(&modes, id)) {
                apply.set_label(&format!("Apply: {}", mode.menu_label()));
            }
        });
    }

    {
        let window = window.clone();
        let parent = parent.clone();
        let action = action.clone();
        let modes = modes.clone();
        apply.connect_clicked(move |_| {
            let chosen = action
                .state()
                .and_then(|s| s.str().and_then(|id| mode_from_id(&modes, id)))
                .unwrap_or(default);
            answer(ReviewChoice::Apply(chosen));
            // Closed directly rather than through close_request: the answer is
            // already printed and the process should go away now.
            window.close();
            parent.close();
        });
    }
    bar.append(&apply);
    bar
}

/// The action-target string for a mode. Serde already names these, so reuse
/// that spelling rather than inventing a second one.
fn mode_id(mode: ApplyMode) -> String {
    serde_json::to_value(mode)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| "full".to_string())
}

fn mode_from_id(modes: &[ApplyMode], id: &str) -> Option<ApplyMode> {
    modes.iter().copied().find(|m| mode_id(*m) == id)
}

/// Print the choice for the daemon. One line of JSON on stdout, flushed --
/// nothing else in this process may write there.
fn answer(choice: ReviewChoice) {
    let mut stdout = std::io::stdout().lock();
    match serde_json::to_string(&choice) {
        Ok(line) => {
            let _ = writeln!(stdout, "{line}");
            let _ = stdout.flush();
        }
        Err(err) => log::error!("failed to encode the review choice: {err}"),
    }
}
