use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};

/// Both of nix's streams. Most callers want stdout; `flake_update` wants
/// stderr, because nix prints the lock-file diff through its warning logger.
pub struct NixOutput {
    pub stdout: String,
    pub stderr: String,
}

/// Run nix with the given arguments. Build logs go to stderr, which is
/// captured and included in errors (and our journal).
fn nix(args: &[&str]) -> Result<NixOutput> {
    log::info!("running: nix {}", args.join(" "));
    let output = Command::new("nix")
        .args(["--extra-experimental-features", "nix-command flakes"])
        .args(args)
        .output()
        .with_context(|| format!("failed to run nix {}", args.join(" ")))?;
    if !output.status.success() {
        bail!(
            "nix {} failed:\n{}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(NixOutput {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

/// Update the worktree's lock file, returning the log nix printed while doing
/// it. That log is the only record of *which inputs moved*, and it arrives on
/// **stderr** -- stdout is empty here.
pub fn flake_update(worktree: &Path) -> Result<String> {
    let wt = worktree.to_string_lossy();
    Ok(nix(&["flake", "update", "--flake", &wt])?.stderr)
}

/// Build an installable with a GC-rooted out-link, returning the store path.
pub fn build(installable: &str, out_link: &Path) -> Result<PathBuf> {
    let link = out_link.to_string_lossy();
    nix(&["build", installable, "--out-link", &link])?;
    std::fs::canonicalize(out_link)
        .with_context(|| format!("resolving out-link {}", out_link.display()))
}

pub fn diff_closures(old: &Path, new: &Path) -> Result<String> {
    let (old, new) = (old.to_string_lossy(), new.to_string_lossy());
    Ok(nix(&["store", "diff-closures", &old, &new])?.stdout)
}
