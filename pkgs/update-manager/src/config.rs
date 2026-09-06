use std::path::PathBuf;
use std::time::Duration;

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

    /// The review dialog binary. Defaults to `stewos-update-review` sitting
    /// next to this executable, which is where the crate's second [[bin]]
    /// lands -- so the daemon and the dialog can never come from different
    /// generations. Without one, the Review entry is not offered.
    #[arg(long, env = "STEWOS_UPDATE_REVIEW_DIALOG")]
    review_dialog: Option<PathBuf>,

    /// Check for updates on this interval without being asked ("6h", "30m",
    /// "1h30m"). A check evaluates only; it downloads and builds nothing
    /// unless --auto-build is also given. Off when absent.
    #[arg(long, env = "STEWOS_UPDATE_CHECK_INTERVAL", value_parser = parse_span)]
    check_interval: Option<Duration>,

    /// Build an update as soon as a scheduled check finds one. Applying is
    /// never automatic.
    #[arg(long, env = "STEWOS_UPDATE_AUTO_BUILD")]
    auto_build: bool,
}

/// "6h", "30m", "90s", "1h30m", "2d": a run of `<number><unit>` pairs. Rejects
/// zero, so an interval is always a real one.
pub fn parse_span(text: &str) -> Result<Duration, String> {
    let mut total = Duration::ZERO;
    let mut number = String::new();
    let mut any = false;
    for c in text.trim().chars() {
        if c.is_ascii_digit() {
            number.push(c);
            continue;
        }
        let value: u64 = number
            .parse()
            .map_err(|_| format!("expected a number before '{c}' in {text:?}"))?;
        number.clear();
        let unit = match c {
            's' => 1,
            'm' => 60,
            'h' => 3600,
            'd' => 86_400,
            other => return Err(format!("unknown unit '{other}' in {text:?}; use s, m, h or d")),
        };
        total += Duration::from_secs(value * unit);
        any = true;
    }
    if !number.is_empty() {
        return Err(format!("{text:?} ends without a unit; use s, m, h or d"));
    }
    if !any || total.is_zero() {
        return Err(format!("{text:?} is not a positive time span"));
    }
    Ok(total)
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
    /// None disables the Review entry: there is no dialog to open.
    pub review_dialog: Option<PathBuf>,
    /// None means checks happen only when asked from the tray.
    pub check_interval: Option<Duration>,
    pub auto_build: bool,
}

/// Find the review dialog next to our own executable.
///
/// This works under makeWrapper too: the wrapper leaves the real binary as
/// `$out/bin/.stewos-update-manager-wrapped`, i.e. the same directory -- unlike
/// the privileged apply helper, which has to climb out to libexec.
fn sibling_dialog() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let candidate = exe.parent()?.join("stewos-update-review");
    candidate.exists().then_some(candidate)
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
            review_dialog: self.review_dialog.or_else(sibling_dialog),
            check_interval: self.check_interval,
            auto_build: self.auto_build,
        })
    }
}

#[cfg(test)]
mod span_tests {
    use super::*;

    #[test]
    fn parses_spans() {
        assert_eq!(parse_span("6h"), Ok(Duration::from_secs(6 * 3600)));
        assert_eq!(parse_span("30m"), Ok(Duration::from_secs(1800)));
        assert_eq!(parse_span("90s"), Ok(Duration::from_secs(90)));
        assert_eq!(parse_span("1h30m"), Ok(Duration::from_secs(5400)));
        assert_eq!(parse_span(" 2d "), Ok(Duration::from_secs(2 * 86_400)));
    }

    /// A rejected flag makes the daemon exit 2 in a restart loop, which the
    /// user sees as the tray icon vanishing -- so be precise about why.
    #[test]
    fn rejects_what_is_not_a_positive_span() {
        assert!(parse_span("").is_err());
        assert!(parse_span("0h").is_err());
        assert!(parse_span("15").is_err());
        assert!(parse_span("h").is_err());
        assert!(parse_span("6 hours").is_err());
        assert!(parse_span("1w").unwrap_err().contains("unknown unit"));
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

    /// The package lists a check compares by evaluation alone, before anything
    /// is built.
    pub fn system_roots_installable(&self) -> String {
        format!(
            "{}#nixosConfigurations.{}.config.environment.systemPackages",
            self.worktree().display(),
            self.host
        )
    }

    pub fn home_roots_installable(&self) -> String {
        format!(
            "{}#homeConfigurations.\"{}@{}\".config.home.packages",
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
