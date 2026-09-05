//! Parser for the lock-file diff `nix flake update` prints.
//!
//! Nix writes this through its *warning* logger, so it arrives on **stderr**,
//! not stdout, and the entries are multi-line:
//!
//! ```text
//! warning: updating lock file '/home/caleb/git/stewos/flake.lock':
//! • Updated input 'nixpkgs':
//!     'github:NixOS/nixpkgs/801bef6…?narHash=sha256-…' (2026-08-20)
//!   → 'github:NixOS/nixpkgs/56c02bc…?narHash=sha256-…' (2026-09-04)
//! • Added input 'caelestia-shell/systems':
//!     'github:nix-systems/default/da67096…?narHash=sha256-…' (2023-04-09)
//! ```
//!
//! Like `diff.rs` this is lenient by design, and for a stronger reason: the
//! format is not a stable API and this is *decoration*. An entry whose value
//! lines never arrive still ships with its name; a line we cannot classify is
//! dropped. `parse` cannot fail, and `do_check` must never gate on it -- a nix
//! output change must not break update checking.

use stewos_update_manager::{InputChange, InputKind};

use super::strip_ansi;

/// Pull the input name out of a `• Updated input 'name':` header.
fn header(line: &str) -> Option<(InputKind, String)> {
    let rest = line.strip_prefix('\u{2022}')?.trim_start();
    for (word, kind) in [
        ("Updated input ", InputKind::Updated),
        ("Added input ", InputKind::Added),
        ("Removed input ", InputKind::Removed),
    ] {
        if let Some(tail) = rest.strip_prefix(word) {
            let name = tail.trim().trim_end_matches(':').trim();
            let name = name.trim_matches('\'');
            if !name.is_empty() {
                return Some((kind, name.to_string()));
            }
        }
    }
    None
}

/// Take the value out of a line: `'github:o/r/rev?narHash=…' (2026-08-20)`.
///
/// Kept **verbatim**, including the trailing date -- that date is how stale the
/// input was, which is worth as much as the rev when reviewing. Shortening it
/// for display is `InputChange::short`'s job, not the parser's.
fn flakeref(line: &str) -> Option<String> {
    let value = line.trim().trim_start_matches('\u{2192}').trim();
    // Must actually look like a value line, or the "warning: updating lock
    // file …" header would be swallowed as one.
    let plausible = value.starts_with('\'') || value.contains(':');
    (!value.is_empty() && plausible).then(|| value.to_string())
}

/// Parse the whole log into one entry per changed input, in the order nix
/// printed them (which is sorted by input attr path).
pub fn parse(log: &str) -> Vec<InputChange> {
    let mut out: Vec<InputChange> = Vec::new();
    for raw in log.lines() {
        let clean = strip_ansi(raw);
        let line = clean.trim_end();
        if line.trim().is_empty() {
            continue;
        }

        if let Some((kind, name)) = header(line.trim()) {
            out.push(InputChange {
                name,
                kind,
                before: None,
                after: None,
            });
            continue;
        }

        // A value line only means anything while an entry is open. This is
        // also what discards the "warning: updating lock file …" header.
        let Some(current) = out.last_mut() else {
            continue;
        };
        let Some(reference) = flakeref(line) else {
            log::debug!("ignoring flake-update line: {line}");
            continue;
        };

        if line.trim_start().starts_with('\u{2192}') {
            current.after = Some(reference);
        } else if current.before.is_none() && current.after.is_none() {
            // An Added input has a single value line and no arrow: that line
            // is its *new* state, not an old one.
            if current.kind == InputKind::Added {
                current.after = Some(reference);
            } else {
                current.before = Some(reference);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Captured verbatim from a real `nix flake update`, header and all.
    const LOG: &str = "\
warning: updating lock file \"/home/caleb/git/stewos/flake.lock\":
\u{2022} Updated input 'nixpkgs':
    'github:NixOS/nixpkgs/801bef6abd86b91e51083066b83fb354a11fc640?narHash=sha256-hLD%3D' (2026-08-20)
  \u{2192} 'github:NixOS/nixpkgs/56c02bcb2a1e1de4dcd0d1d0f7ab0b0e0c9d3f11?narHash=sha256-gzT%3D' (2026-09-04)
\u{2022} Added input 'caelestia-shell/systems':
    'github:nix-systems/default/da67096a3b9bf56a91d16901293e51ba5b49a27e?narHash=sha256-Vy1%3D' (2023-04-09)
";

    #[test]
    fn parses_a_real_log() {
        let inputs = parse(LOG);
        assert_eq!(inputs.len(), 2);

        assert_eq!(inputs[0].name, "nixpkgs");
        assert_eq!(inputs[0].kind, InputKind::Updated);
        // The value line is kept verbatim, so the date nix printed survives to
        // the dialog -- how stale an input was is worth as much as its rev.
        assert_eq!(
            InputChange::short(inputs[0].before.as_deref().unwrap()),
            "801bef6 (2026-08-20)"
        );
        assert_eq!(
            InputChange::short(inputs[0].after.as_deref().unwrap()),
            "56c02bc (2026-09-04)"
        );

        // An added input has no "before": its single value line is the new one.
        assert_eq!(inputs[1].name, "caelestia-shell/systems");
        assert_eq!(inputs[1].kind, InputKind::Added);
        assert!(inputs[1].before.is_none());
        assert_eq!(
            InputChange::short(inputs[1].after.as_deref().unwrap()),
            "da67096 (2023-04-09)"
        );
        assert!(!inputs[1].is_top_level());
    }

    #[test]
    fn tolerates_colour() {
        let coloured = "\u{2022} \u{1b}[1mUpdated input 'nixpkgs':\u{1b}[0m\n    'github:NixOS/nixpkgs/abc' (2026-01-01)\n";
        let inputs = parse(coloured);
        assert_eq!(inputs.len(), 1);
        assert_eq!(inputs[0].name, "nixpkgs");
    }

    /// A truncated entry must still ship, with the ref it never saw left None.
    #[test]
    fn tolerates_a_missing_arrow_line() {
        let truncated = "\u{2022} Updated input 'nixpkgs':\n    'github:NixOS/nixpkgs/abc' (2026-01-01)\n";
        let inputs = parse(truncated);
        assert_eq!(inputs.len(), 1);
        assert!(inputs[0].before.is_some());
        assert!(inputs[0].after.is_none());
    }

    #[test]
    fn removed_inputs_carry_neither_ref() {
        let inputs = parse("\u{2022} Removed input 'old-thing'\n");
        assert_eq!(inputs.len(), 1);
        assert_eq!(inputs[0].kind, InputKind::Removed);
        assert!(inputs[0].before.is_none() && inputs[0].after.is_none());
    }

    #[test]
    fn an_empty_log_yields_nothing() {
        assert!(parse("").is_empty());
        // The bare warning header on its own is not an entry.
        assert!(parse("warning: updating lock file '/x/flake.lock':\n").is_empty());
    }
}
