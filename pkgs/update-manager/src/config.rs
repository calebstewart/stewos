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
}

#[derive(Debug, Clone)]
pub struct Config {
    pub flake: PathBuf,
    pub host: String,
    pub user: String,
    pub branch: String,
    pub cache_dir: PathBuf,
    pub icon_dir: Option<PathBuf>,
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

        Ok(Config {
            flake,
            host,
            user,
            branch: self.branch,
            cache_dir,
            icon_dir: self.icon_dir,
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
