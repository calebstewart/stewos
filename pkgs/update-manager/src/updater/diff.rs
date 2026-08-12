//! Parser for `nix store diff-closures` output.
//!
//! The output format is not a stable API, so the parser is deliberately
//! lenient: a line it cannot classify counts as an upgrade rather than being
//! dropped, so the summary errs toward overstating changes.

use std::collections::BTreeMap;

use crate::state::Counts;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Change {
    Added,
    Removed,
    Upgraded,
}

/// Parse one diff into package-name → change kind.
pub fn parse(output: &str) -> BTreeMap<String, Change> {
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
        let (name, rest) = (name.trim(), rest.trim());
        if name.is_empty() {
            continue;
        }

        let change = match rest.split_once('\u{2192}') {
            Some((left, right)) => {
                // Version list on either side; the trailing ", +1.2 MiB" size
                // delta rides along with the right-hand side.
                let right = right
                    .rsplit_once(',')
                    .map(|(versions, size)| {
                        if size.trim().ends_with("iB") || size.trim().ends_with('B') {
                            versions
                        } else {
                            right
                        }
                    })
                    .unwrap_or(right);
                let all = |side: &str, only: &str| {
                    !side.trim().is_empty()
                        && side.split(',').all(|v| v.trim() == only)
                };
                if all(left, "\u{2205}") {
                    Change::Added
                } else if all(right, "\u{2205}") {
                    Change::Removed
                } else {
                    Change::Upgraded
                }
            }
            // No arrow: a size-only delta ("dconf: -6.0 KiB") means the
            // package was rebuilt at the same version.
            None => Change::Upgraded,
        };
        changes.insert(name.to_string(), change);
    }
    changes
}

pub fn counts(changes: &BTreeMap<String, Change>) -> Counts {
    let mut c = Counts::default();
    for change in changes.values() {
        match change {
            Change::Added => c.added += 1,
            Change::Removed => c.removed += 1,
            Change::Upgraded => c.upgraded += 1,
        }
    }
    c
}

/// Union of two diffs keyed by package name, so closure members shared by the
/// system and home targets are not double-counted. Conflicting classifications
/// collapse to Upgraded (the package exists on both sides overall).
pub fn merge(
    a: &BTreeMap<String, Change>,
    b: &BTreeMap<String, Change>,
) -> BTreeMap<String, Change> {
    let mut merged = a.clone();
    for (name, change) in b {
        merged
            .entry(name.clone())
            .and_modify(|existing| {
                if *existing != *change {
                    *existing = Change::Upgraded;
                }
            })
            .or_insert(*change);
    }
    merged
}

fn strip_ansi(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&n) = chars.peek() {
                    chars.next();
                    if n.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else {
            out.push(c);
        }
    }
    out
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
        assert_eq!(changes["firefox"], Change::Upgraded);
        assert_eq!(changes["new-tool"], Change::Added);
        assert_eq!(changes["old-tool"], Change::Removed);
        assert_eq!(changes["multi"], Change::Upgraded);
        assert_eq!(changes["dconf"], Change::Upgraded);

        let c = counts(&changes);
        assert_eq!((c.upgraded, c.added, c.removed), (3, 1, 1));
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
        assert_eq!(changes["foo"], Change::Upgraded);
    }

    #[test]
    fn merge_deduplicates_and_resolves_conflicts() {
        let system = parse("shared: 1.0 \u{2192} 2.0\nsys-only: \u{2205} \u{2192} 1.0");
        let home = parse("shared: 1.0 \u{2192} 2.0\nhome-only: 1.0 \u{2192} \u{2205}");
        let merged = merge(&system, &home);
        assert_eq!(merged.len(), 3);
        assert_eq!(counts(&merged).upgraded, 1);

        // Added in one target, upgraded in the other → counted once, as upgraded.
        let a = parse("pkg: \u{2205} \u{2192} 1.0");
        let b = parse("pkg: 0.9 \u{2192} 1.0");
        assert_eq!(merge(&a, &b)["pkg"], Change::Upgraded);
    }
}
