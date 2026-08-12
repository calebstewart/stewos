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
