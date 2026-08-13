use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "stewos-update-manager", version, about)]
pub struct Args {
    /// Git checkout of the flake to update and merge back into
    #[arg(long, env = "STEWOS_UPDATE_FLAKE")]
    flake: Option<PathBuf>,

    /// Flake attribute name of this machine (defaults to the hostname)
    #[arg(long, env = "STEWOS_UPDATE_HOST")]
    host: Option<String>,

    /// User name of the homeConfigurations attribute (defaults to $USER)
    #[arg(long, env = "STEWOS_UPDATE_USER")]
    user: Option<String>,

    /// Branch the update check builds on
    #[arg(long, default_value = "stewos-update")]
    branch: String,

    /// Directory for the worktree, build out-links and persisted state
    #[arg(long)]
    cache_dir: Option<PathBuf>,

    /// Icon-theme root holding the rendered status icons. Set by the wrapper;
    /// without it the tray falls back to the ambient icon theme's names.
    #[arg(long, env = "STEWOS_UPDATE_ICON_DIR")]
    icon_dir: Option<PathBuf>,

    /// Terminal emulator the troubleshooting entries open in (defaults to
    /// $TERMINAL). Without one, those entries are not offered at all.
    #[arg(long, env = "STEWOS_UPDATE_TERMINAL")]
    terminal: Option<String>,

    /// Argument that makes the terminal run a command, repeatable. Passing any
    /// replaces the default, so a terminal taking the command positionally is
    /// spelled `--terminal-arg ""`. Values here are almost always flags, hence
    /// allow_hyphen_values -- without it clap reads `-e` as an option of ours.
    #[arg(long, default_value = "-e", allow_hyphen_values = true)]
    terminal_arg: Vec<String>,

    /// Editor the failure report opens in (defaults to $EDITOR, then nvim)
    #[arg(long, env = "STEWOS_UPDATE_EDITOR")]
    editor: Option<String>,

    /// Claude Code executable used by the troubleshooting session
    #[arg(long, env = "STEWOS_UPDATE_CLAUDE", default_value = "claude")]
    claude: String,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub flake: PathBuf,
    pub host: String,
    pub user: String,
    pub branch: String,
    pub cache_dir: PathBuf,
    pub icon_dir: Option<PathBuf>,
    /// None disables the troubleshooting entries: there is nothing to open
    /// them in.
    pub terminal: Option<String>,
    pub terminal_args: Vec<String>,
    pub editor: String,
    pub claude: String,
}

impl Args {
    pub fn resolve(self) -> Result<Config> {
        let home = std::env::var("HOME").context("HOME is not set")?;

        let flake = self
            .flake
            .unwrap_or_else(|| PathBuf::from(&home).join("git/stewos"));

        let host = match self.host {
            Some(h) => h,
            None => std::fs::read_to_string("/proc/sys/kernel/hostname")
                .context("failed to read hostname")?
                .trim()
                .to_string(),
        };

        let user = match self.user {
            Some(u) => u,
            None => std::env::var("USER").context("USER is not set")?,
        };

        let cache_dir = self.cache_dir.unwrap_or_else(|| {
            std::env::var("XDG_CACHE_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from(&home).join(".cache"))
                .join("stewos-update-manager")
        });

        let terminal = self.terminal.or_else(|| std::env::var("TERMINAL").ok());
        let editor = self
            .editor
            .or_else(|| std::env::var("EDITOR").ok())
            .unwrap_or_else(|| "nvim".to_string());

        Ok(Config {
            flake,
            host,
            user,
            branch: self.branch,
            cache_dir,
            icon_dir: self.icon_dir,
            terminal,
            // An empty argument is how a terminal that takes its command
            // positionally is spelled; drop it rather than passing "" on.
            terminal_args: self
                .terminal_arg
                .into_iter()
                .filter(|a| !a.is_empty())
                .collect(),
            editor,
            claude: self.claude,
        })
    }
}

impl Config {
    pub fn worktree(&self) -> PathBuf {
        self.cache_dir.join("worktree")
    }

    pub fn result_system(&self) -> PathBuf {
        self.cache_dir.join("result-system")
    }

    pub fn result_home(&self) -> PathBuf {
        self.cache_dir.join("result-home")
    }

    pub fn state_file(&self) -> PathBuf {
        self.cache_dir.join("state.json")
    }

    /// Where the failure report is written. One stable path, overwritten on
    /// every troubleshooting request, so it survives a daemon restart and can
    /// be reopened by hand.
    pub fn troubleshoot_file(&self) -> PathBuf {
        self.cache_dir.join("troubleshoot.md")
    }

    pub fn system_installable(&self) -> String {
        format!(
            "{}#nixosConfigurations.{}.config.system.build.toplevel",
            self.worktree().display(),
            self.host
        )
    }

    pub fn home_installable(&self) -> String {
        format!(
            "{}#homeConfigurations.\"{}@{}\".activationPackage",
            self.worktree().display(),
            self.user,
            self.host
        )
    }

    /// The current home-manager profile, if one exists. Standalone
    /// home-manager has moved this over time, so probe both locations.
    pub fn home_profile(&self) -> Option<PathBuf> {
        let state_home = std::env::var("XDG_STATE_HOME")
            .map(PathBuf::from)
            .ok()
            .or_else(|| {
                std::env::var("HOME")
                    .map(|h| PathBuf::from(h).join(".local/state"))
                    .ok()
            })?;

        let candidates = [
            state_home.join("nix/profiles/home-manager"),
            PathBuf::from("/nix/var/nix/profiles/per-user")
                .join(&self.user)
                .join("home-manager"),
        ];
        candidates.into_iter().find(|p| p.exists())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `-e` is a *value*, not a flag of ours. Without `allow_hyphen_values`
    /// clap rejects the very default it is given, and the daemon exits 2 in a
    /// restart loop -- which looks from the outside like the tray icon simply
    /// disappearing. Nothing else checks that the default and the parser agree.
    #[test]
    fn terminal_args_may_start_with_a_hyphen() {
        let args = Args::parse_from(["stewos-update-manager", "--terminal-arg", "-e"]);
        assert_eq!(args.terminal_arg, vec!["-e".to_string()]);

        let defaulted = Args::parse_from(["stewos-update-manager"]);
        assert_eq!(defaulted.terminal_arg, vec!["-e".to_string()]);
    }
}
