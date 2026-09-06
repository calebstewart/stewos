//! The packages a configuration installs directly, without building anything.
//!
//! `environment.systemPackages` and `home.packages` are lists of derivations
//! whose names are known at evaluation time, so their old and new versions can
//! be compared in a couple of seconds. This is the "these packages changed"
//! list the pre-build review shows. It is deliberately *not* the closure diff:
//! a library bump underneath everything shows up here only as the dry run's
//! path count, and the full picture arrives with `diff-closures` once the
//! build is done. Diffing the derivation graph instead was measured and
//! rejected -- 752 "changed" names against 141 real ones.
//!
//! The name/version split is nix's own (`builtins.parseDrvName`), evaluated
//! inside the `--apply`, so a name like `python3.12-requests-2.31.0` is cut
//! where nix cuts it.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result};
use serde::Deserialize;
use stewos_update_manager::{Change, Counts, PackageChange, Scope};

/// The `--apply` expression: a list of `{ name, version }`.
pub const APPLY: &str = "ps: map (p: builtins.parseDrvName (p.name or \"\")) ps";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Root {
    pub name: String,
    pub version: String,
}

pub fn parse(json: &str) -> Result<Vec<Root>> {
    serde_json::from_str(json).context("parsing the package roots nix evaluated")
}

fn by_name(roots: &[Root]) -> BTreeMap<&str, BTreeSet<&str>> {
    let mut map: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for root in roots {
        if root.name.is_empty() {
            continue;
        }
        map.entry(&root.name).or_default().insert(&root.version);
    }
    map
}

/// One row per package whose set of versions differs between the two sides.
/// Never a size: nothing has been built.
pub fn diff(old: &[Root], new: &[Root], scope: Scope) -> Vec<PackageChange> {
    let (old, new) = (by_name(old), by_name(new));
    let names: BTreeSet<&str> = old.keys().chain(new.keys()).copied().collect();
    let versions = |set: Option<&BTreeSet<&str>>| -> Vec<String> {
        set.map(|s| s.iter().filter(|v| !v.is_empty()).map(|v| v.to_string()).collect())
            .unwrap_or_default()
    };
    names
        .into_iter()
        .filter_map(|name| {
            let (before, after) = (old.get(name), new.get(name));
            if before == after {
                return None;
            }
            let change = match (before, after) {
                (None, _) => Change::Added,
                (_, None) => Change::Removed,
                _ => Change::Upgraded,
            };
            Some(PackageChange {
                name: name.to_string(),
                change,
                before: versions(before),
                after: versions(after),
                size: None,
                scope,
            })
        })
        .collect()
}

pub fn counts(rows: &[PackageChange]) -> Counts {
    let mut counts = Counts::default();
    for row in rows {
        match row.change {
            Change::Upgraded => counts.upgraded += 1,
            Change::Added => counts.added += 1,
            Change::Removed => counts.removed += 1,
        }
    }
    counts
}

/// Counts over the union of both scopes, deduplicated by name, so a package in
/// both lists is one change rather than two.
pub fn total(rows: &[PackageChange]) -> Counts {
    let mut seen: BTreeMap<&str, Change> = BTreeMap::new();
    for row in rows {
        seen.entry(&row.name).or_insert(row.change);
    }
    let mut counts = Counts::default();
    for change in seen.values() {
        match change {
            Change::Upgraded => counts.upgraded += 1,
            Change::Added => counts.added += 1,
            Change::Removed => counts.removed += 1,
        }
    }
    counts
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(name: &str, version: &str) -> Root {
        Root {
            name: name.into(),
            version: version.into(),
        }
    }

    #[test]
    fn parses_what_the_apply_expression_yields() {
        let roots = parse(r#"[{"name":"nixvim","version":""},{"name":"firefox","version":"155.0"}]"#).unwrap();
        assert_eq!(roots, vec![root("nixvim", ""), root("firefox", "155.0")]);
        assert!(parse("not json").is_err());
    }

    #[test]
    fn classifies_changes_and_ignores_the_unchanged() {
        let old = vec![
            root("firefox", "154.0"),
            root("eza", "0.23.5"),
            root("nixvim", ""),
            root("gone", "1.0"),
        ];
        let new = vec![
            root("firefox", "155.0"),
            root("eza", "0.23.5"),
            root("nixvim", ""),
            root("fresh", "2.0"),
        ];
        let rows = diff(&old, &new, Scope::Home);
        let names: Vec<&str> = rows.iter().map(|r| r.name.as_str()).collect();
        assert_eq!(names, vec!["firefox", "fresh", "gone"]);
        assert_eq!(rows[0].change, Change::Upgraded);
        assert_eq!(rows[0].before, vec!["154.0"]);
        assert_eq!(rows[0].after, vec!["155.0"]);
        assert_eq!(rows[1].change, Change::Added);
        assert_eq!(rows[1].before, Vec::<String>::new());
        assert_eq!(rows[2].change, Change::Removed);
        assert!(rows.iter().all(|r| r.size.is_none() && r.scope == Scope::Home));

        let c = counts(&rows);
        assert_eq!((c.upgraded, c.added, c.removed), (1, 1, 1));
    }

    #[test]
    fn several_versions_of_one_name_are_one_row() {
        let old = vec![root("python3", "3.12.4"), root("python3", "3.13.1")];
        let new = vec![root("python3", "3.12.4"), root("python3", "3.13.2")];
        let rows = diff(&old, &new, Scope::System);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].before, vec!["3.12.4", "3.13.1"]);
        assert_eq!(rows[0].after, vec!["3.12.4", "3.13.2"]);
    }

    #[test]
    fn total_deduplicates_across_scopes() {
        let old = vec![root("git", "2.50")];
        let new = vec![root("git", "2.51")];
        let mut rows = diff(&old, &new, Scope::System);
        rows.extend(diff(&old, &new, Scope::Home));
        assert_eq!(rows.len(), 2);
        assert_eq!(total(&rows).upgraded, 1);
    }
}
