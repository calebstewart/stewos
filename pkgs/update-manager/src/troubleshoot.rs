//! Turning a failure into something a person (or an agent) can work with.
//!
//! When a check or an apply fails, the anyhow chain already carries the failing
//! command's stderr, but it only ever reached the journal and a truncated
//! tooltip. This module records the failure, renders it into one deterministic
//! Markdown report, and opens that report in the user's terminal -- either in
//! their editor, or as the opening prompt of a Claude Code session rooted in
//! the flake checkout.
//!
//! The report is written when the user asks for it, not when the failure
//! happened, so the environment it describes -- git state, the journal -- is
//! the state they are about to debug.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{anyhow, bail, Context, Result};

use crate::config::Config;
use crate::ApplyMode;

/// How many lines of our own journal to quote.
const LOG_LINES: &str = "150";

/// Ceilings for the two sections that quote something unbounded. A failing
/// `nix build` puts its whole log in both the error chain and the journal, and
/// a report nobody can read through is not worth writing.
const MAX_ERROR: usize = 32 * 1024;
const MAX_LOG: usize = 24 * 1024;

/// Which operation was running when the failure happened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Operation {
    Check,
    Apply(ApplyMode),
}

impl Operation {
    fn describe(self) -> String {
        match self {
            Operation::Check => "update check".to_string(),
            Operation::Apply(mode) => format!("apply ({})", mode.describe()),
        }
    }

    /// The closing section of the report: what the daemon was doing, and the
    /// guards that shape what a fix is allowed to look like.
    fn guidance(self) -> &'static str {
        match self {
            Operation::Check => {
                "The check runs entirely in the worktree above: it fast-forwards the \
                 branch onto `main`, runs `nix flake update`, then builds the system \
                 and home closures and diffs them against what is running. Nothing \
                 was applied and `main` was not touched, so the failure is either in \
                 the git bookkeeping or in evaluating/building one of the two \
                 installables listed above -- try building the one that failed by \
                 hand from the worktree."
            }
            Operation::Apply(_) => {
                "The apply is idempotent by design: the OS half is skipped when the \
                 system profile already points at the new generation, and the home \
                 half when the home-manager profile does, so retrying is safe and \
                 resumes rather than repeats. The OS half runs through `run0`, which \
                 escalates via polkit, and the lock bump is fast-forwarded into \
                 `main` before home activation -- because activating home can restart \
                 this very daemon. Work out which of those three steps the error \
                 above came from before changing anything."
            }
        }
    }
}

/// A recorded failure. Held in memory by the worker only: it quotes the current
/// boot's journal, so persisting it across a restart would describe a session
/// that no longer exists.
#[derive(Debug, Clone)]
pub struct ErrorReport {
    pub operation: Operation,
    /// When the failure happened, as opposed to when the report was written.
    pub when: String,
    /// The full anyhow chain, deliberately not truncated the way the tooltip's
    /// copy is.
    pub message: String,
}

impl ErrorReport {
    pub fn new(operation: Operation, message: String) -> Self {
        Self {
            operation,
            when: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
            message,
        }
    }
}

/// What to open the report in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// The user's editor.
    Report,
    /// A Claude Code session in the flake checkout.
    Claude,
}

/// Render the report and write it to [`Config::troubleshoot_file`].
pub fn write(cfg: &Config, report: &ErrorReport) -> Result<PathBuf> {
    let path = cfg.troubleshoot_file();
    std::fs::write(&path, render(cfg, report))
        .with_context(|| format!("writing {}", path.display()))?;
    log::info!("wrote failure report to {}", path.display());
    Ok(path)
}

/// Open a written report, in a terminal of its own.
pub fn launch(cfg: &Config, action: Action, report: &Path) -> Result<()> {
    let terminal = cfg
        .terminal
        .as_ref()
        .ok_or_else(|| anyhow!("no terminal is configured; pass --terminal"))?;

    // The terminal is spawned in the flake checkout, so a missing one fails
    // the spawn with an ENOENT that reads as if the terminal were missing.
    if !cfg.flake.is_dir() {
        bail!("flake checkout {} does not exist", cfg.flake.display());
    }

    let inner = inner_argv(cfg, action, report);

    log::info!("opening {terminal} for {inner:?}");
    let mut child = Command::new(terminal)
        .args(&cfg.terminal_args)
        .args(&inner)
        .current_dir(&cfg.flake)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("failed to run {terminal}"))?;

    // Nothing waits on these otherwise, and a session's worth of closed
    // troubleshooting windows would pile up as zombies.
    std::thread::spawn(move || {
        if let Err(err) = child.wait() {
            log::warn!("terminal wait failed: {err}");
        }
    });
    Ok(())
}

/// What to run inside the terminal.
fn inner_argv(cfg: &Config, action: Action, report: &Path) -> Vec<String> {
    match action {
        Action::Report => vec![cfg.editor.clone(), report.display().to_string()],
        Action::Claude => vec![
            cfg.claude.clone(),
            // The report lives in the cache directory, outside the flake
            // checkout the session is rooted in.
            "--add-dir".to_string(),
            cfg.cache_dir.display().to_string(),
            // `--add-dir` takes *directories...*, so without this the prompt is
            // read as another directory and the session opens with nothing
            // submitted.
            "--".to_string(),
            prompt(report),
        ],
    }
}

/// The opening turn of the Claude session. A positional prompt starts an
/// interactive session with it already submitted; the report is named in prose
/// rather than with an `@` reference, which is a CLAUDE.md import syntax and
/// not a documented feature of the prompt itself.
fn prompt(report: &Path) -> String {
    format!(
        "The StewOS update-manager daemon just failed. Read the failure report at {} \
         -- it has the error, the configuration it ran with, the git state and the \
         daemon's own log -- then investigate this flake checkout and work out what \
         broke and how to fix it. Do not change anything until we agree on the cause.",
        report.display()
    )
}

fn render(cfg: &Config, report: &ErrorReport) -> String {
    let flake = cfg.flake.display().to_string();
    let worktree = cfg.worktree().display().to_string();

    let mut out = String::new();
    out.push_str("# StewOS update-manager failure\n\n");
    out.push_str(&format!(
        "Written {} by stewos-update-manager {}.\n\n",
        chrono::Local::now().format("%Y-%m-%d %H:%M:%S"),
        env!("CARGO_PKG_VERSION"),
    ));

    out.push_str("## Operation\n\n");
    out.push_str(&format!("- Operation: {}\n", report.operation.describe()));
    out.push_str(&format!("- Failed at: {}\n\n", report.when));

    out.push_str("## Error\n\n```text\n");
    out.push_str(&elide(report.message.trim_end(), MAX_ERROR));
    out.push_str("\n```\n\n");

    out.push_str("## Configuration\n\n");
    out.push_str("| Key | Value |\n| --- | --- |\n");
    let profile = match cfg.home_profile() {
        Some(path) => path.display().to_string(),
        None => "none found".to_string(),
    };
    let cache_dir = cfg.cache_dir.display().to_string();
    let system_installable = cfg.system_installable();
    let home_installable = cfg.home_installable();
    for (key, value) in [
        ("flake", flake.as_str()),
        ("worktree", worktree.as_str()),
        ("branch", cfg.branch.as_str()),
        ("host", cfg.host.as_str()),
        ("user", cfg.user.as_str()),
        ("cache dir", cache_dir.as_str()),
        ("system installable", system_installable.as_str()),
        ("home installable", home_installable.as_str()),
        ("home profile", profile.as_str()),
    ] {
        out.push_str(&format!("| {key} | `{value}` |\n"));
    }
    out.push('\n');

    out.push_str("## Repository\n\n```text\n");
    out.push_str(&capture(
        "git",
        &["-C", &flake, "status", "--short", "--branch"],
    ));
    out.push_str(&capture("git", &["-C", &flake, "log", "--oneline", "-5"]));
    out.push_str(&capture(
        "git",
        &["-C", &flake, "rev-parse", "main", &cfg.branch],
    ));
    out.push_str(&capture(
        "git",
        &["-C", &worktree, "status", "--short", "--branch"],
    ));
    out.push_str("```\n\n");

    out.push_str("## Daemon log\n\n```text\n");
    out.push_str(&elide(&journal(), MAX_LOG));
    out.push_str("```\n\n");

    out.push_str("## What to investigate\n\n");
    out.push_str(report.operation.guidance());
    out.push('\n');
    out
}

/// The daemon's own journal. Selecting on the invocation id gets exactly this
/// run of the unit; a bare `cargo run` has no invocation, so fall back to the
/// syslog identifier env_logger's stderr is tagged with.
fn journal() -> String {
    match std::env::var("INVOCATION_ID") {
        Ok(id) if !id.is_empty() => capture(
            "journalctl",
            &[
                "--user",
                &format!("_SYSTEMD_INVOCATION_ID={id}"),
                "-n",
                LOG_LINES,
                "--no-pager",
            ],
        ),
        _ => capture(
            "journalctl",
            &[
                "--user",
                "-t",
                "stewos-update-manager",
                "-n",
                LOG_LINES,
                "--no-pager",
            ],
        ),
    }
}

/// Bound a section, keeping both ends: the head is our own framing of what
/// failed, the tail is where a build log actually says why.
fn elide(text: &str, max: usize) -> String {
    if text.len() <= max {
        return text.to_string();
    }
    let head_end = floor_boundary(text, max / 4);
    let tail_start = ceil_boundary(text, text.len() - (max - max / 4));
    format!(
        "{}\n[\u{2026} {} bytes elided; the full text is in the journal \u{2026}]\n{}",
        &text[..head_end],
        tail_start - head_end,
        &text[tail_start..]
    )
}

fn floor_boundary(text: &str, mut at: usize) -> usize {
    while at > 0 && !text.is_char_boundary(at) {
        at -= 1;
    }
    at
}

fn ceil_boundary(text: &str, mut at: usize) -> usize {
    while at < text.len() && !text.is_char_boundary(at) {
        at += 1;
    }
    at
}

/// Run a command and quote it whatever it does. Unlike the wrappers in
/// `updater::{git,nix}` this never fails: a report that dropped the output of
/// the command that went wrong would be missing the interesting part.
fn capture(prog: &str, args: &[&str]) -> String {
    let mut out = format!("$ {prog} {}\n", args.join(" "));
    match Command::new(prog).args(args).output() {
        Ok(output) => {
            if !output.status.success() {
                out.push_str(&format!("[{}]\n", output.status));
            }
            for stream in [&output.stdout, &output.stderr] {
                let text = String::from_utf8_lossy(stream);
                let text = text.trim_end();
                if !text.is_empty() {
                    out.push_str(text);
                    out.push('\n');
                }
            }
        }
        Err(err) => out.push_str(&format!("[could not run: {err}]\n")),
    }
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> Config {
        Config {
            flake: PathBuf::from("/home/u/git/stewos"),
            host: "host".to_string(),
            user: "u".to_string(),
            branch: "stewos-update".to_string(),
            cache_dir: PathBuf::from("/home/u/.cache/stewos-update-manager"),
            icon_dir: None,
            terminal: Some("alacritty".to_string()),
            terminal_args: vec!["-e".to_string()],
            editor: "nvim".to_string(),
            claude: "claude".to_string(),
        }
    }

    /// `--add-dir` is variadic, so the prompt has to sit past a `--` or Claude
    /// reads it as another directory and opens an empty session -- which looks
    /// like the seeding simply not working.
    #[test]
    fn claude_prompt_is_separated_from_add_dir() {
        let argv = inner_argv(&cfg(), Action::Claude, Path::new("/tmp/report.md"));
        let separator = argv.iter().position(|a| a == "--").expect("no -- in argv");
        let prompt = argv.len() - 1;
        assert_eq!(separator, prompt - 1, "the prompt must follow -- directly");
        assert!(argv[prompt].contains("/tmp/report.md"));
    }

    #[test]
    fn report_opens_in_the_editor() {
        let argv = inner_argv(&cfg(), Action::Report, Path::new("/tmp/report.md"));
        assert_eq!(argv, vec!["nvim".to_string(), "/tmp/report.md".to_string()]);
    }
}
