//! Types shared by the daemon and the review dialog.
//!
//! The two binaries in this crate are separate processes talking over a pipe,
//! and this module is the only thing they agree on. Everything here is
//! serde-able because it all crosses that pipe; the wire spellings are pinned
//! by tests at the bottom, since a silent rename would only show up at runtime.

use serde::{Deserialize, Serialize};

/// Bumped whenever [`ReviewRequest`] changes shape. A home activation can leave
/// an old daemon running against a new dialog binary until the unit restarts,
/// so the dialog checks this rather than misparsing.
pub const PROTOCOL_VERSION: u32 = 1;

/// What an apply should cover. Only the variants that touch the OS need
/// privileged execution (via run0); a home-only apply runs entirely as the
/// user.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ApplyMode {
    /// Switch the OS now and activate home.
    Full,
    /// Activate home only; the OS part stays pending.
    HomeOnly,
    /// Activate home and stage the OS generation for the next boot.
    HomeAndBoot,
    /// Switch the OS now only; the home part stays pending.
    SystemOnly,
}

impl ApplyMode {
    /// The order the review dialog offers them in, default first.
    pub const MENU_ORDER: [ApplyMode; 4] = [
        ApplyMode::Full,
        ApplyMode::SystemOnly,
        ApplyMode::HomeOnly,
        ApplyMode::HomeAndBoot,
    ];

    /// Long form for a notification body: "home now, system on next boot".
    pub fn describe(self) -> &'static str {
        match self {
            ApplyMode::Full => "system + home",
            ApplyMode::HomeOnly => "home only",
            ApplyMode::HomeAndBoot => "home now, system on next boot",
            ApplyMode::SystemOnly => "system only",
        }
    }

    /// Short label for the review dialog's Apply menu, where the button reads
    /// "Apply: {label}" and there is no room for the full sentence.
    ///
    /// `HomeAndBoot` is deliberately *not* "System (next boot)": it activates
    /// home **now** and only defers the system half, so it is the All option
    /// with the system part staged, not a system-only deferral.
    pub fn menu_label(self) -> &'static str {
        match self {
            ApplyMode::Full => "All",
            ApplyMode::SystemOnly => "System",
            ApplyMode::HomeOnly => "Home",
            ApplyMode::HomeAndBoot => "All (System next boot)",
        }
    }
}

/// How one package changed between the two closures.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Change {
    Added,
    Removed,
    Upgraded,
}

/// Which closure a package came from. Free to compute -- the two diffs are
/// already separate -- and it is what lets the dialog group the rows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Scope {
    System,
    Home,
}

/// One package's row in the review dialog.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageChange {
    pub name: String,
    pub change: Change,
    /// Versions on each side, with `∅` already dropped -- it is not a version.
    /// **Both empty is normal and must render honestly**: it means the store
    /// path changed at the same version (a rebuild), or a line the lenient
    /// parser could not classify. Do not invent an arrow for those.
    pub before: Vec<String>,
    pub after: Vec<String>,
    /// The closure size delta exactly as nix printed it ("+1.3 MiB"), when it
    /// printed one. This is the only thing a rebuild row has to show.
    pub size: Option<String>,
    pub scope: Scope,
}

impl PackageChange {
    /// True when nix reported no version on either side: same version, new
    /// store path.
    pub fn is_rebuild(&self) -> bool {
        self.before.is_empty() && self.after.is_empty()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum InputKind {
    Updated,
    Added,
    Removed,
}

/// One `• Updated input 'x'` entry from `nix flake update`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InputChange {
    /// Input attr path as nix prints it: "nixpkgs", "home-manager/nixpkgs".
    pub name: String,
    pub kind: InputKind,
    /// Locked flakerefs verbatim. `None` when nix printed none (an Added input
    /// has no before, a Removed one has neither) or the parser missed it.
    pub before: Option<String>,
    pub after: Option<String>,
}

impl InputChange {
    /// True for an input this flake declares itself, as opposed to one pulled
    /// in by another input. The dialog lists these and only counts the rest.
    pub fn is_top_level(&self) -> bool {
        !self.name.contains('/')
    }

    /// Display form of a value line: a long rev cut to 7 and the query string
    /// dropped, with nix's trailing `(date)` kept.
    ///
    /// `'github:o/r/1234567890abcdef…?narHash=…' (2026-08-20)` reads
    /// `1234567 (2026-08-20)`. The date matters as much as the rev when
    /// reviewing -- it is how stale the input was.
    ///
    /// Lives here rather than in the dialog because it formats data the daemon
    /// owns, and the daemon's own logs should read the same way.
    pub fn short(reference: &str) -> String {
        let text = reference.trim();

        // Nix appends " (YYYY-MM-DD)" after the quoted ref.
        let (head, date) = match text.rsplit_once('(') {
            Some((head, tail)) if tail.ends_with(')') => {
                (head.trim(), Some(tail.trim_end_matches(')').trim()))
            }
            _ => (text, None),
        };

        // Unwrap the quotes nix puts round the ref itself.
        let url = match (head.find('\''), head.rfind('\'')) {
            (Some(a), Some(b)) if b > a => &head[a + 1..b],
            _ => head,
        };

        let bare = url.split('?').next().unwrap_or(url);
        let last = bare.rsplit('/').next().unwrap_or(bare);
        let is_rev = last.len() >= 32 && last.chars().all(|c| c.is_ascii_hexdigit());
        let rev = if is_rev { &last[..7] } else { last };

        match date {
            Some(date) if !date.is_empty() => format!("{rev} ({date})"),
            _ => rev.to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Counts {
    pub upgraded: u32,
    pub added: u32,
    pub removed: u32,
}

impl Counts {
    pub fn is_zero(&self) -> bool {
        self.upgraded == 0 && self.added == 0 && self.removed == 0
    }

    /// Compact tally for a tooltip or a section heading: "12↑ 3+ 1−".
    pub fn arrows(&self) -> String {
        format!(
            "{}\u{2191} {}+ {}\u{2212}",
            self.upgraded, self.added, self.removed
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Summary {
    /// Union of the system and home diffs, deduplicated by package name.
    pub total: Counts,
    pub system: Counts,
    pub home: Counts,
}

impl Summary {
    /// Short menu/notification line: "12 updated, 3 new, 1 removed".
    pub fn short(&self) -> String {
        if self.total.is_zero() {
            "Lock updated, no package changes".to_string()
        } else {
            format!(
                "{} updated, {} new, {} removed",
                self.total.upgraded, self.total.added, self.total.removed
            )
        }
    }

    /// Per-target breakdown for the tooltip.
    pub fn breakdown(&self) -> String {
        format!(
            "System: {} \u{00b7} Home: {}",
            self.system.arrows(),
            self.home.arrows()
        )
    }
}

/// What the daemon hands the dialog on stdin, as one line of JSON.
///
/// This is a *snapshot*. The daemon re-validates everything at apply time, so a
/// request that has gone stale simply produces an apply the daemon refuses --
/// the dialog is never the authority on what is pending.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReviewRequest {
    pub version: u32,
    pub host: String,
    pub summary: Summary,
    #[serde(default)]
    pub packages: Vec<PackageChange>,
    #[serde(default)]
    pub inputs: Vec<InputChange>,
    /// The apply modes to offer, in the order to offer them. Render exactly
    /// these; the daemon may narrow the list later without a protocol bump.
    pub modes: Vec<ApplyMode>,
}

/// What the dialog prints on stdout, as one line of JSON -- or nothing at all
/// if the window was closed without a choice.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ReviewChoice {
    Apply(ApplyMode),
    Dismiss,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// These spellings are the entire contract between two separate processes.
    /// A rename that compiles on both sides would otherwise fail silently at
    /// runtime, so pin them.
    #[test]
    fn wire_spellings_are_stable() {
        let j = |m: ApplyMode| serde_json::to_string(&ReviewChoice::Apply(m)).unwrap();
        assert_eq!(j(ApplyMode::Full), r#"{"apply":"full"}"#);
        assert_eq!(j(ApplyMode::HomeOnly), r#"{"apply":"home-only"}"#);
        assert_eq!(j(ApplyMode::HomeAndBoot), r#"{"apply":"home-and-boot"}"#);
        assert_eq!(j(ApplyMode::SystemOnly), r#"{"apply":"system-only"}"#);
        assert_eq!(
            serde_json::to_string(&ReviewChoice::Dismiss).unwrap(),
            r#""dismiss""#
        );
    }

    #[test]
    fn choices_round_trip() {
        for mode in ApplyMode::MENU_ORDER {
            let choice = ReviewChoice::Apply(mode);
            let encoded = serde_json::to_string(&choice).unwrap();
            assert_eq!(serde_json::from_str::<ReviewChoice>(&encoded).unwrap(), choice);
        }
    }

    #[test]
    fn shortens_revs_but_not_names() {
        // The whole value line as nix prints it, quotes and date included.
        assert_eq!(
            InputChange::short(
                "'github:NixOS/nixpkgs/801bef6abd86b91e51083066b83fb354a11fc640?narHash=sha256-x%3D' (2026-08-20)"
            ),
            "801bef6 (2026-08-20)"
        );
        // A bare ref with no date still works.
        assert_eq!(
            InputChange::short(
                "github:NixOS/nixpkgs/801bef6abd86b91e51083066b83fb354a11fc640?narHash=sha256-x%3D"
            ),
            "801bef6"
        );
        // A tag or branch is already short and is not hex: leave it alone.
        assert_eq!(InputChange::short("github:numtide/flake-utils/v1.0.0"), "v1.0.0");
        assert_eq!(InputChange::short("path:/etc/nixos"), "nixos");
    }

    #[test]
    fn top_level_inputs_have_no_slash() {
        let mk = |name: &str| InputChange {
            name: name.to_string(),
            kind: InputKind::Updated,
            before: None,
            after: None,
        };
        assert!(mk("nixpkgs").is_top_level());
        assert!(!mk("caelestia-shell/systems").is_top_level());
    }

    #[test]
    fn a_rebuild_has_no_versions_on_either_side() {
        let mk = |before: Vec<&str>, after: Vec<&str>| PackageChange {
            name: "hyprland".into(),
            change: Change::Upgraded,
            before: before.into_iter().map(String::from).collect(),
            after: after.into_iter().map(String::from).collect(),
            size: Some("-983.8 KiB".into()),
            scope: Scope::System,
        };
        assert!(mk(vec![], vec![]).is_rebuild());
        assert!(!mk(vec!["1.0"], vec!["1.1"]).is_rebuild());
    }
}
