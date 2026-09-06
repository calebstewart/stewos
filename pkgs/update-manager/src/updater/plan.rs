//! Parser for the plan `nix build --dry-run` prints.
//!
//! ```text
//! these 3 derivations will be built:
//!   /nix/store/…-stewos-update-manager-0.1.0.drv
//! these 386 paths will be fetched (445.1 MiB download, 1.7 GiB unpacked):
//!   /nix/store/…-abseil-cpp-20210324.2
//! ```
//!
//! Human text on stderr: `--json` carries only the output paths, and
//! `--log-format internal-json` wraps these same lines as `msg` records. Like
//! `inputs.rs` the parser is lenient -- a nix format change must produce an
//! empty plan, not a failed check -- and the plan is worth having on its own:
//! the two counts are the exact denominator of the build's progress, because
//! nix's `copyPaths` and `builds` activities count the same things.

use stewos_update_manager::BuildPlan;

use super::strip_ansi;

/// "445.1 MiB" → bytes, in the binary units nix prints. Precision is a tenth
/// of a unit, which is plenty for a progress bar.
pub fn parse_size(text: &str) -> Option<u64> {
    let mut words = text.split_whitespace();
    let number: f64 = words.next()?.parse().ok()?;
    let scale: f64 = match words.next()? {
        "B" => 1.0,
        "KiB" => 1024.0,
        "MiB" => 1024.0 * 1024.0,
        "GiB" => 1024.0 * 1024.0 * 1024.0,
        "TiB" => 1024.0 * 1024.0 * 1024.0 * 1024.0,
        _ => return None,
    };
    Some((number * scale).round() as u64)
}

/// The count off the front of "386 paths" / "3 derivations", or 1 for the
/// singular forms "path" / "derivation".
fn count(head: &str) -> u32 {
    head.split_whitespace()
        .next()
        .and_then(|word| word.parse().ok())
        .unwrap_or(1)
}

pub fn parse(stderr: &str) -> BuildPlan {
    let mut plan = BuildPlan::default();
    for raw in stderr.lines() {
        let line = strip_ansi(raw);
        let line = line.trim();
        let Some(rest) = line
            .strip_prefix("these ")
            .or_else(|| line.strip_prefix("this "))
        else {
            continue;
        };
        let Some((head, tail)) = rest.split_once(" will be ") else {
            continue;
        };
        if tail.starts_with("built") {
            plan.derivations = count(head);
        } else if tail.starts_with("fetched") {
            plan.paths = count(head);
            // "(445.1 MiB download, 1.7 GiB unpacked)"
            if let Some(sizes) = tail.split_once('(').and_then(|(_, s)| s.split(')').next()) {
                for part in sizes.split(',') {
                    let part = part.trim();
                    if let Some(size) = part.strip_suffix("download") {
                        plan.download_bytes = parse_size(size).unwrap_or(0);
                    } else if let Some(size) = part.strip_suffix("unpacked") {
                        plan.unpacked_bytes = parse_size(size).unwrap_or(0);
                    }
                }
            }
        }
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_full_plan() {
        let text = "\
these 3 derivations will be built:
  /nix/store/aaa-foo.drv
  /nix/store/bbb-bar.drv
  /nix/store/ccc-baz.drv
these 386 paths will be fetched (445.1 MiB download, 1.7 GiB unpacked):
  /nix/store/ddd-abseil-cpp-20210324.2
";
        let plan = parse(text);
        assert_eq!(plan.derivations, 3);
        assert_eq!(plan.paths, 386);
        assert_eq!(plan.download_bytes, 466_721_178);
        assert_eq!(plan.unpacked_bytes, 1_825_361_101);
    }

    #[test]
    fn singular_forms_count_one() {
        let plan = parse(
            "this derivation will be built:\n  /nix/store/a.drv\n\
             this path will be fetched (52.0 KiB download, 1.1 MiB unpacked):\n  /nix/store/b\n",
        );
        assert_eq!(plan.derivations, 1);
        assert_eq!(plan.paths, 1);
        assert_eq!(plan.download_bytes, 53_248);
    }

    #[test]
    fn nothing_to_do_is_an_empty_plan() {
        assert_eq!(parse(""), BuildPlan::default());
        assert_eq!(parse("warning: something unrelated\n"), BuildPlan::default());
    }

    #[test]
    fn strips_colour() {
        let plan = parse("\x1b[1mthese 2 paths will be fetched (1.0 MiB download, 2.0 MiB unpacked):\x1b[0m\n");
        assert_eq!(plan.paths, 2);
        assert_eq!(plan.download_bytes, 1_048_576);
    }

    #[test]
    fn sizes_in_every_unit() {
        assert_eq!(parse_size("512 B"), Some(512));
        assert_eq!(parse_size("1.5 KiB"), Some(1536));
        assert_eq!(parse_size("2.0 GiB"), Some(2_147_483_648));
        assert_eq!(parse_size("1.0 TiB"), Some(1_099_511_627_776));
        assert_eq!(parse_size("12 MB"), None);
        assert_eq!(parse_size("lots"), None);
    }
}
