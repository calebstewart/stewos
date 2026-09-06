use std::path::Path;
use std::process::Command;

use anyhow::{anyhow, bail, Context, Result};

/// Run git in `dir`, returning trimmed stdout, with stderr in the error.
pub fn git(dir: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .with_context(|| format!("failed to run git {}", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "git {} failed in {}:\n{}",
            args.join(" "),
            dir.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn rev_parse(repo: &Path, rev: &str) -> Result<String> {
    git(repo, &["rev-parse", "--verify", rev])
}

/// Does `path` have uncommitted (staged or unstaged) changes in `repo`?
pub fn path_dirty(repo: &Path, path: &str) -> Result<bool> {
    Ok(!git(repo, &["status", "--porcelain", "--", path])?.is_empty())
}

/// The blob hash of `path` as it is on disk in `dir`, committed or not. It
/// identifies an updated lock file without committing it.
pub fn hash_object(dir: &Path, path: &str) -> Result<String> {
    git(dir, &["hash-object", "--", path])
}

/// The currently checked-out branch of `repo`, or None when detached.
pub fn current_branch(repo: &Path) -> Result<Option<String>> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["symbolic-ref", "--short", "-q", "HEAD"])
        .output()
        .context("failed to run git symbolic-ref")?;
    if output.status.success() {
        Ok(Some(
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
        ))
    } else {
        Ok(None)
    }
}

/// Create or refresh the update worktree with `branch` reset onto main.
pub fn ensure_worktree(flake: &Path, worktree: &Path, branch: &str) -> Result<()> {
    git(flake, &["worktree", "prune"])?;

    let wt = worktree
        .to_str()
        .ok_or_else(|| anyhow!("worktree path is not valid UTF-8"))?;

    if !worktree.join(".git").exists() {
        git(flake, &["worktree", "add", "-B", branch, wt, "main"])?;
        return Ok(());
    }

    let refresh = || -> Result<()> {
        git(worktree, &["checkout", "-B", branch, "main"])?;
        git(worktree, &["reset", "--hard", "main"])?;
        git(worktree, &["clean", "-fdx"])?;
        Ok(())
    };
    if let Err(err) = refresh() {
        // A broken worktree is disposable: recreate it once from scratch.
        log::warn!("worktree refresh failed, recreating: {err:#}");
        let _ = git(flake, &["worktree", "remove", "--force", wt]);
        let _ = git(flake, &["worktree", "prune"]);
        git(flake, &["worktree", "add", "-B", branch, wt, "main"])?;
    }
    Ok(())
}

/// Has flake.lock changed in the worktree relative to HEAD?
pub fn lock_changed(worktree: &Path) -> Result<bool> {
    let status = Command::new("git")
        .arg("-C")
        .arg(worktree)
        .args(["diff", "--quiet", "--", "flake.lock"])
        .status()
        .context("failed to run git diff")?;
    Ok(!status.success())
}

pub fn commit_lock(worktree: &Path) -> Result<()> {
    git(worktree, &["add", "flake.lock"])?;
    git(worktree, &["commit", "-m", "flake: update inputs"])?;
    Ok(())
}

/// Fast-forward `main` in the user's checkout to the update branch. Only ever
/// fast-forwards; any failure leaves the checkout untouched.
pub fn merge_back(flake: &Path, branch: &str) -> Result<()> {
    if current_branch(flake)?.as_deref() == Some("main") {
        git(flake, &["merge", "--ff-only", branch])?;
    } else {
        // Not on main: fast-forward the ref without touching the working tree.
        let refspec = format!("{branch}:main");
        git(flake, &["fetch", ".", &refspec])?;
    }
    Ok(())
}

/// Everything `git status --porcelain` reports for `repo`, untracked files
/// included. Ignored files are not: they are invisible to a build either way.
///
/// Not through [`git`]: that trims stdout, and the first line's status
/// columns can begin with a space (` M flake.lock`).
pub fn status_porcelain(repo: &Path) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["status", "--porcelain", "--untracked-files=all"])
        .output()
        .context("failed to run git status")?;
    if !output.status.success() {
        bail!(
            "git status failed in {}:\n{}",
            repo.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Why an update cannot proceed, from a porcelain status; `None` when the
/// checkout is clean.
///
/// Any change at all blocks, not only `flake.lock`: the worktree builds from
/// committed `main`, so uncommitted work would be invisible to the build and
/// then fought over when the lock bump is fast-forwarded back.
pub fn blocked_reason(porcelain: &str, flake: &Path) -> Option<String> {
    let names: Vec<&str> = porcelain
        .lines()
        .filter(|line| line.len() > 3)
        .map(|line| line[3..].trim())
        .filter(|name| !name.is_empty())
        .collect();
    if names.is_empty() {
        return None;
    }
    let shown = names.iter().take(3).copied().collect::<Vec<_>>().join(", ");
    let more = names.len().saturating_sub(3);
    let suffix = if more > 0 {
        format!(" (+{more} more)")
    } else {
        String::new()
    };
    Some(format!("Local changes in {}: {shown}{suffix}", flake.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_clean_checkout_is_not_blocked() {
        assert_eq!(blocked_reason("", Path::new("/f")), None);
        assert_eq!(blocked_reason("\n\n", Path::new("/f")), None);
    }

    #[test]
    fn tracked_and_untracked_changes_both_block() {
        assert_eq!(
            blocked_reason(" M flake.lock\n", Path::new("/home/u/git/stewos")).as_deref(),
            Some("Local changes in /home/u/git/stewos: flake.lock")
        );
        assert_eq!(
            blocked_reason("?? modules/new.nix\n", Path::new("/f")).as_deref(),
            Some("Local changes in /f: modules/new.nix")
        );
    }

    #[test]
    fn many_changes_are_summarised() {
        let status = " M a\nA  b\n?? c\nD  d\nR  e -> f\n";
        assert_eq!(
            blocked_reason(status, Path::new("/f")).as_deref(),
            Some("Local changes in /f: a, b, c (+2 more)")
        );
    }

    #[test]
    fn odd_lines_never_panic() {
        assert_eq!(blocked_reason("M\n??\n x", Path::new("/f")), None);
    }
}
