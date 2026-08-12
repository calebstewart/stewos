use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};

/// Run nix with the given arguments, returning stdout. Build logs go to
/// stderr, which is captured and included in errors (and our journal).
fn nix(args: &[&str]) -> Result<String> {
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
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub fn flake_update(worktree: &Path) -> Result<()> {
    let wt = worktree.to_string_lossy();
    nix(&["flake", "update", "--flake", &wt])?;
    Ok(())
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
    nix(&["store", "diff-closures", &old, &new])
}
