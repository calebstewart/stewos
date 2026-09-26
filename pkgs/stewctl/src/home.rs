//! Generations of a home-manager profile. nh builds and switches homes but
//! keeps no verb for their generations, so stewctl reads the profile itself:
//! `home-manager-<N>-link` beside a `home-manager` link to the current one,
//! which is all `home-manager generations` does too.

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, PartialEq, Eq)]
pub struct Generation {
    pub number: u32,
    pub link: PathBuf,
    pub current: bool,
    pub created: Option<SystemTime>,
}

/// Where home-manager keeps the profile: the XDG state directory, or the
/// per-user profile directory older installs used.
pub fn profile_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    let state = std::env::var_os("XDG_STATE_HOME")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".local/state")));
    if let Some(state) = state {
        dirs.push(state.join("nix/profiles"));
    }
    if let Some(user) = std::env::var_os("USER") {
        dirs.push(Path::new("/nix/var/nix/profiles/per-user").join(user));
    }
    dirs
}

fn number(name: &str) -> Option<u32> {
    name.strip_prefix("home-manager-")?
        .strip_suffix("-link")?
        .parse()
        .ok()
}

pub fn generations(dir: &Path) -> Result<Vec<Generation>> {
    let current = std::fs::read_link(dir.join("home-manager"))
        .ok()
        .and_then(|t| t.file_name().and_then(|n| number(&n.to_string_lossy())));
    let mut found = Vec::new();
    for entry in std::fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))? {
        let entry = entry?;
        let Some(n) = number(&entry.file_name().to_string_lossy()) else {
            continue;
        };
        found.push(Generation {
            number: n,
            link: entry.path(),
            current: current == Some(n),
            created: entry
                .path()
                .symlink_metadata()
                .and_then(|m| m.modified())
                .ok(),
        });
    }
    found.sort_by_key(|g| g.number);
    Ok(found)
}

pub fn find_profile() -> Result<PathBuf> {
    profile_dirs()
        .into_iter()
        .find(|d| d.join("home-manager").exists())
        .context("no home-manager profile found; has this home been switched yet?")
}

/// The generation a rollback goes to: `n`, or the newest before the current.
pub fn rollback_target(gens: &[Generation], n: Option<u32>) -> Result<&Generation> {
    let current = gens.iter().find(|g| g.current).map(|g| g.number);
    match n {
        Some(n) => match gens.iter().find(|g| g.number == n) {
            Some(g) if g.current => bail!("generation {n} is already current"),
            Some(g) => Ok(g),
            None => bail!("there is no home generation {n}"),
        },
        None => {
            let current = current.context("cannot tell which home generation is current")?;
            gens.iter()
                .rev()
                .find(|g| g.number < current)
                .with_context(|| format!("there is no home generation before {current}"))
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn profile(links: &[u32], current: u32) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "stewctl-test-{}-{}",
            std::process::id(),
            links
                .iter()
                .map(u32::to_string)
                .collect::<Vec<_>>()
                .join("-")
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for n in links {
            symlink("/nonexistent", dir.join(format!("home-manager-{n}-link"))).unwrap();
        }
        symlink(
            format!("home-manager-{current}-link"),
            dir.join("home-manager"),
        )
        .unwrap();
        std::fs::write(dir.join("profile"), "").unwrap();
        dir
    }

    #[test]
    fn lists_and_picks_the_previous_generation() {
        let dir = profile(&[3, 10, 7], 10);
        let gens = generations(&dir).unwrap();
        assert_eq!(
            gens.iter().map(|g| g.number).collect::<Vec<_>>(),
            [3, 7, 10]
        );
        assert!(gens[2].current);
        assert_eq!(rollback_target(&gens, None).unwrap().number, 7);
        assert_eq!(rollback_target(&gens, Some(3)).unwrap().number, 3);
        assert!(rollback_target(&gens, Some(10)).is_err());
        assert!(rollback_target(&gens, Some(4)).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn the_oldest_generation_has_nothing_before_it() {
        let dir = profile(&[1, 2], 1);
        let gens = generations(&dir).unwrap();
        assert!(rollback_target(&gens, None).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
