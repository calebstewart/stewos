//! Parser for `nix store diff-closures` output.
//!
//! The output format is not a stable API, so the parser is deliberately
//! lenient: a line it cannot classify counts as an upgrade rather than being
//! dropped, so the summary errs toward overstating changes.
//!
//! It keeps the version lists and the size delta as well as the
//! classification. Those used to be read purely as classification hints and
//! thrown away; the review dialog renders them.

use std::collections::BTreeMap;

use stewos_update_manager::{Change, Counts};

use super::strip_ansi;

/// Nix's marker for "not present on this side". It is not a version, so it is
/// dropped from the version lists rather than stored.
const ABSENT: &str = "\u{2205}";

/// One package's line. `before`/`after` hold whatever versions nix printed.
///
/// **Both empty is normal**: it means the store path changed at the same
/// version (nix prints only a size delta), or the line could not be
/// classified. Renderers must not invent an arrow for those.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageDiff {
    pub change: Change,
    pub before: Vec<String>,
    pub after: Vec<String>,
    /// The closure size delta exactly as nix printed it, when it printed one.
    pub size: Option<String>,
}

/// Does this field look like nix's trailing size delta ("-8.3 MiB", "1.3 MiB")
/// rather than a version? Versions do not end in a bare `B`.
fn looks_like_size(field: &str) -> bool {
    let f = field.trim();
    f.ends_with('B') && f.chars().any(|c| c.is_ascii_digit())
}

/// Split a `1.2, 1.3` version list, dropping `∅` and blanks. `ε` is kept: it
/// means "present but unversioned", which is different from absent.
fn versions(side: &str) -> Vec<String> {
    side.split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty() && *v != ABSENT)
        .map(String::from)
        .collect()
}

/// Is every entry on this side `∅`, i.e. the package is absent here?
fn all_absent(side: &str) -> bool {
    !side.trim().is_empty() && side.split(',').all(|v| v.trim() == ABSENT)
}

/// Parse one diff into package-name → change.
pub fn parse(output: &str) -> BTreeMap<String, PackageDiff> {
    let mut changes = BTreeMap::new();
    for raw in output.lines() {
        let line = strip_ansi(raw);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Some((name, rest)) = line.split_once(':') else {
            log::warn!("unparseable diff-closures line: {line}");
            continue;
        };
        let (name, mut rest) = (name.trim(), rest.trim());
        if name.is_empty() {
            continue;
        }

        // The trailing ", +1.2 MiB" rides along with the right-hand side.
        // Version lists are themselves comma-separated, so only the last field
        // can be the size.
        let mut size = None;
        match rest.rsplit_once(',') {
            Some((head, tail)) if looks_like_size(tail) => {
                size = Some(tail.trim().to_string());
                rest = head;
            }
            // No comma at all and the whole remainder is a size: nix printed
            // only a size delta ("hyprland: -983.8 KiB"), meaning the package
            // was rebuilt at the same version.
            None if looks_like_size(rest) => {
                size = Some(rest.trim().to_string());
                rest = "";
            }
            _ => {}
        }

        let diff = match rest.split_once('\u{2192}') {
            Some((left, right)) => PackageDiff {
                change: if all_absent(left) {
                    Change::Added
                } else if all_absent(right) {
                    Change::Removed
                } else {
                    Change::Upgraded
                },
                before: versions(left),
                after: versions(right),
                size,
            },
            // No arrow: a rebuild, or a line we could not read. Either way the
            // lenient contract says count it as an upgrade -- but with no
            // versions, so it renders honestly rather than as a fake bump.
            None => PackageDiff {
                change: Change::Upgraded,
                before: Vec::new(),
                after: Vec::new(),
                size,
            },
        };
        changes.insert(name.to_string(), diff);
    }
    changes
}

pub fn counts(changes: &BTreeMap<String, PackageDiff>) -> Counts {
    let mut c = Counts::default();
    for diff in changes.values() {
        match diff.change {
            Change::Added => c.added += 1,
            Change::Removed => c.removed += 1,
            Change::Upgraded => c.upgraded += 1,
        }
    }
    c
}

/// Merge `other`'s versions into `existing`, preserving first-seen order and
/// skipping duplicates.
fn absorb(existing: &mut PackageDiff, other: &PackageDiff) {
    if existing.change != other.change {
        existing.change = Change::Upgraded;
    }
    for (dst, src) in [
        (&mut existing.before, &other.before),
        (&mut existing.after, &other.after),
    ] {
        for v in src {
            if !dst.contains(v) {
                dst.push(v.clone());
            }
        }
    }
    if existing.size.is_none() {
        existing.size = other.size.clone();
    }
}

/// Union of two diffs keyed by package name, so closure members shared by the
/// system and home targets are not double-counted. Conflicting classifications
/// collapse to Upgraded (the package exists on both sides overall).
pub fn merge(
    a: &BTreeMap<String, PackageDiff>,
    b: &BTreeMap<String, PackageDiff>,
) -> BTreeMap<String, PackageDiff> {
    let mut merged = a.clone();
    for (name, diff) in b {
        merged
            .entry(name.clone())
            .and_modify(|existing| absorb(existing, diff))
            .or_insert_with(|| diff.clone());
    }
    merged
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_typical_diff() {
        let output = "\
firefox: 120.0.1 \u{2192} 121.0, +5.2 MiB
new-tool: \u{2205} \u{2192} 1.0, +10.2 KiB
old-tool: 2.0 \u{2192} \u{2205}, -3.0 KiB
multi: 1.2, 1.3 \u{2192} 1.4
dconf: -6.0 KiB
";
        let changes = parse(output);
        assert_eq!(changes["firefox"].change, Change::Upgraded);
        assert_eq!(changes["new-tool"].change, Change::Added);
        assert_eq!(changes["old-tool"].change, Change::Removed);
        assert_eq!(changes["multi"].change, Change::Upgraded);
        assert_eq!(changes["dconf"].change, Change::Upgraded);

        // Versions are retained, and the size delta never leaks into them.
        assert_eq!(changes["firefox"].before, ["120.0.1"]);
        assert_eq!(changes["firefox"].after, ["121.0"]);
        assert_eq!(changes["firefox"].size.as_deref(), Some("+5.2 MiB"));
        assert_eq!(changes["multi"].before, ["1.2", "1.3"]);
        assert_eq!(changes["multi"].after, ["1.4"]);
        assert!(changes["multi"].size.is_none());

        // `∅` is absence, not a version, so it is dropped from the lists.
        assert!(changes["new-tool"].before.is_empty());
        assert_eq!(changes["new-tool"].after, ["1.0"]);
        assert!(changes["old-tool"].after.is_empty());

        // The lenient-parser contract: a size-only line is an upgrade with no
        // versions at all, which is what lets a renderer say "rebuilt".
        assert!(changes["dconf"].before.is_empty());
        assert!(changes["dconf"].after.is_empty());
        assert_eq!(changes["dconf"].size.as_deref(), Some("-6.0 KiB"));

        let c = counts(&changes);
        assert_eq!((c.upgraded, c.added, c.removed), (3, 1, 1));
    }

    /// Real lines from this machine that broke earlier drafts: a multi-version
    /// add whose list is comma-separated *and* carries a size, and `ε`, which
    /// means "present but unversioned" and must survive.
    #[test]
    fn handles_real_world_shapes() {
        let output = "\
rnnoise-plugin: \u{2205} \u{2192} 1.10, 1.10-lv2, 1.10-vst3, 69.1 MiB
99-noise: \u{2205} \u{2192} \u{3b5}
getty: \u{3b5} \u{2192} \u{2205}
hyprland: -983.8 KiB
";
        let changes = parse(output);
        assert_eq!(changes["rnnoise-plugin"].change, Change::Added);
        assert_eq!(
            changes["rnnoise-plugin"].after,
            ["1.10", "1.10-lv2", "1.10-vst3"]
        );
        assert_eq!(changes["rnnoise-plugin"].size.as_deref(), Some("69.1 MiB"));

        assert_eq!(changes["99-noise"].change, Change::Added);
        assert_eq!(changes["99-noise"].after, ["\u{3b5}"]);
        assert_eq!(changes["getty"].change, Change::Removed);
        assert_eq!(changes["getty"].before, ["\u{3b5}"]);

        assert_eq!(changes["hyprland"].size.as_deref(), Some("-983.8 KiB"));
        assert!(changes["hyprland"].before.is_empty());
    }

    #[test]
    fn empty_output_means_no_changes() {
        assert!(parse("").is_empty());
        assert!(parse("\n\n").is_empty());
    }

    #[test]
    fn strips_ansi_codes() {
        let output = "\u{1b}[1mfoo\u{1b}[0m: 1.0 \u{2192} 2.0";
        let changes = parse(output);
        assert_eq!(changes["foo"].change, Change::Upgraded);
    }

    #[test]
    fn merge_deduplicates_and_resolves_conflicts() {
        let system = parse("shared: 1.0 \u{2192} 2.0\nsys-only: \u{2205} \u{2192} 1.0");
        let home = parse("shared: 1.0 \u{2192} 2.0\nhome-only: 1.0 \u{2192} \u{2205}");
        let merged = merge(&system, &home);
        assert_eq!(merged.len(), 3);
        assert_eq!(counts(&merged).upgraded, 1);

        // Added in one target, upgraded in the other → counted once, as
        // upgraded, and no `∅` leaks into the union.
        let a = parse("pkg: \u{2205} \u{2192} 1.0");
        let b = parse("pkg: 0.9 \u{2192} 1.0");
        let m = merge(&a, &b);
        assert_eq!(m["pkg"].change, Change::Upgraded);
        assert_eq!(m["pkg"].before, ["0.9"]);
        assert_eq!(m["pkg"].after, ["1.0"]);
    }

    #[test]
    fn merge_unions_version_lists() {
        let a = parse("shared: 1.0 \u{2192} 2.0");
        let b = parse("shared: 1.0 \u{2192} 2.1");
        let m = merge(&a, &b);
        assert_eq!(m["shared"].before, ["1.0"]);
        assert_eq!(m["shared"].after, ["2.0", "2.1"]);
    }
}
