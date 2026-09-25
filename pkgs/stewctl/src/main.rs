//! stewctl: build and switch this machine's StewOS configurations, the same
//! way on NixOS, macOS and Windows.
//!
//! It is a dispatcher. nh does the work on NixOS and macOS and the winpkgs
//! runtime does it on Windows; stewctl only decides which configuration (see
//! `identity`) and what each verb becomes there (see `plan`).

mod cli;
mod home;
mod identity;
mod plan;

use anyhow::{bail, Context, Result};
use clap::Parser;
use cli::{Cli, Target};
use identity::{Host, Kind, Resolved};
use plan::{Step, Winpkgs};
use std::io::Write;
use std::path::Path;
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    if let Some(code) = legacy_steward_switch() {
        return code;
    }
    if let Some(code) = bare_verb() {
        return code;
    }
    match run(Cli::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("stewctl: {e:#}");
            ExitCode::FAILURE
        }
    }
}

/// `stewctl switch --if-running` was steward's command before steward's
/// control CLI was renamed, and every home generation from before the rename
/// still runs it on activation -- `winpkgs home rollback` included. It must
/// never reach the unified CLI (where a switch is a rebuild), so it is handed
/// to steward's renamed CLI, or does nothing when there is none: exactly what
/// the old line did when steward was not installed.
fn legacy_steward_switch() -> Option<ExitCode> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args != ["switch", "--if-running"] {
        return None;
    }
    Some(match Command::new("stewardctl").args(&args).status() {
        Ok(status) => exit_code(status),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("stewctl: running stewardctl: {e}");
            ExitCode::FAILURE
        }
    })
}

/// nh's shape: a verb belongs to a target, and nothing applies both. Say so
/// rather than leave clap's "unrecognized subcommand".
fn bare_verb() -> Option<ExitCode> {
    let first = std::env::args().nth(1)?;
    let verbs = [
        "build",
        "switch",
        "boot",
        "test",
        "diff",
        "plan",
        "generations",
        "info",
        "rollback",
        "clean",
        "gc",
        "repl",
        "status",
    ];
    if !verbs.contains(&first.as_str()) {
        return None;
    }
    eprintln!(
        "stewctl: `{first}` needs a target: `stewctl os {first}` for the system, \
         `stewctl home {first}` for this user"
    );
    Some(ExitCode::from(2))
}

fn winpkgs() -> Winpkgs {
    let base = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| "%LOCALAPPDATA%".into());
    Winpkgs {
        cli: Path::new(&base)
            .join("winpkgs")
            .join("runtime")
            .join("cli.ps1")
            .display()
            .to_string(),
    }
}

fn run(cli: Cli) -> Result<ExitCode> {
    let host = Host::detect()?;
    let w = winpkgs();

    let (steps, resolved, print) = match cli.target {
        Target::Os {
            verb,
            common,
            host: attr,
        } => {
            let r = host.resolve(Kind::Os, common.flake.as_deref(), attr.as_deref())?;
            (plan::plan(&r, &verb, &common, &w)?, Some(r), common.print)
        }
        Target::Home {
            verb,
            common,
            configuration,
        } => {
            let r = host.resolve(
                Kind::Home,
                common.flake.as_deref(),
                configuration.as_deref(),
            )?;
            (plan::plan(&r, &verb, &common, &w)?, Some(r), common.print)
        }
        Target::Flake { common, args } => {
            let flake = host.flake(Kind::Os, common.flake.as_deref())?;
            // `nix flake` runs in the checkout; a flake reference such as
            // github:owner/repo has none. (C:\... on Windows is a path.)
            if !host.windows && flake.value.contains(':') {
                bail!("{} is not a local checkout", flake.value);
            }
            // Only Windows differs: the command goes to the distro.
            let platform = host.native.unwrap_or(identity::Platform::Nixos);
            (
                vec![plan::plan_flake(platform, &flake.value, &args, &w)],
                None,
                common.print,
            )
        }
    };

    if print {
        for step in &steps {
            println!("{step}");
        }
        return Ok(ExitCode::SUCCESS);
    }
    for step in &steps {
        match execute(step, resolved.as_ref())? {
            Flow::Continue => {}
            Flow::Stop(code) => return Ok(code),
        }
    }
    Ok(ExitCode::SUCCESS)
}

enum Flow {
    Continue,
    Stop(ExitCode),
}

fn execute(step: &Step, resolved: Option<&Resolved>) -> Result<Flow> {
    match step {
        Step::Run { program, args, cwd } => {
            let mut cmd = Command::new(program);
            cmd.args(args);
            if let Some(cwd) = cwd {
                cmd.current_dir(cwd);
            }
            let status = cmd.status().with_context(|| format!("running {program}"))?;
            if !status.success() {
                return Ok(Flow::Stop(exit_code(status)));
            }
        }
        Step::Confirm(prompt) => {
            print!("{prompt} [y/N] ");
            std::io::stdout().flush()?;
            let mut answer = String::new();
            std::io::stdin().read_line(&mut answer)?;
            if !matches!(answer.trim(), "y" | "Y" | "yes") {
                return Ok(Flow::Stop(ExitCode::SUCCESS));
            }
        }
        Step::HomeGenerations => {
            let dir = home::find_profile()?;
            for g in home::generations(&dir)? {
                let age = g
                    .created
                    .and_then(|t| t.elapsed().ok())
                    .map(|d| format!("{}d ago", d.as_secs() / 86_400))
                    .unwrap_or_default();
                let mark = if g.current { "  (current)" } else { "" };
                println!("{:>5}  {:>9}  {}{mark}", g.number, age, g.link.display());
            }
        }
        Step::HomeRollback(n) => {
            let dir = home::find_profile()?;
            let gens = home::generations(&dir)?;
            let target = home::rollback_target(&gens, *n)?;
            eprintln!("activating home generation {}", target.number);
            let status = Command::new(target.link.join("activate"))
                .status()
                .context("running the generation's activate script")?;
            if !status.success() {
                return Ok(Flow::Stop(exit_code(status)));
            }
        }
        Step::Status => {
            let r = resolved.context("nothing resolved")?;
            let kind = match r.kind {
                Kind::Os => "os",
                Kind::Home => "home",
            };
            println!("target     {kind} ({})", r.platform);
            println!("flake      {}  [{}]", r.flake.value, r.flake.source);
            println!("attribute  {}  [{}]", r.attribute.value, r.attribute.source);
        }
    }
    Ok(Flow::Continue)
}

fn exit_code(status: std::process::ExitStatus) -> ExitCode {
    match status.code() {
        Some(c) => ExitCode::from(u8::try_from(c).unwrap_or(1)),
        None => ExitCode::FAILURE,
    }
}
