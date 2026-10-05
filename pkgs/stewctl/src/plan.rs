//! What a verb becomes on each platform: a list of steps, most of them a
//! command for nh or winpkgs to run. Pure, so the whole dispatch table is
//! tested without touching a machine.

use crate::cli::{Common, Verb};
use crate::identity::{Kind, Platform, Resolved};
use anyhow::Result;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    Run {
        program: String,
        args: Vec<String>,
        /// Run in this directory rather than the current one.
        cwd: Option<String>,
    },
    /// Ask on the terminal; stop, successfully, unless the answer is yes.
    Confirm(String),
    /// List a home-manager profile's generations (nh has no verb for it).
    HomeGenerations,
    /// Activate an earlier home-manager generation.
    HomeRollback(Option<u32>),
    /// Print what was resolved.
    Status,
}

impl fmt::Display for Step {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Step::Run { program, args, cwd } => {
                if let Some(cwd) = cwd {
                    write!(f, "(cd {} && ", quote(cwd))?;
                }
                write!(f, "{}", quote(program))?;
                for a in args {
                    write!(f, " {}", quote(a))?;
                }
                if cwd.is_some() {
                    write!(f, ")")?;
                }
                Ok(())
            }
            Step::Confirm(prompt) => write!(f, "# ask: {prompt}"),
            Step::HomeGenerations => write!(f, "# list home-manager generations"),
            Step::HomeRollback(Some(n)) => write!(f, "# activate home-manager generation {n}"),
            Step::HomeRollback(None) => {
                write!(f, "# activate the previous home-manager generation")
            }
            Step::Status => write!(f, "# print status"),
        }
    }
}

fn quote(s: &str) -> String {
    if !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_./:@=+%\\".contains(c))
    {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', r"'\''"))
    }
}

fn run(program: &str, args: impl IntoIterator<Item = impl Into<String>>) -> Step {
    Step::Run {
        program: program.into(),
        args: args.into_iter().map(Into::into).collect(),
        cwd: None,
    }
}

/// Where the winpkgs CLI lives: installed by `winpkgs.cli` in every home.
pub struct Winpkgs {
    pub cli: String,
}

impl Winpkgs {
    fn step(&self, flake: &str, args: impl IntoIterator<Item = impl Into<String>>) -> Step {
        // Named parameters first: cli.ps1 gathers everything after the verb
        // into its passthrough.
        let mut all: Vec<String> = vec![
            "-NoProfile".into(),
            "-File".into(),
            self.cli.clone(),
            "-Flake".into(),
            flake.into(),
        ];
        all.extend(args.into_iter().map(Into::into));
        run("pwsh", all)
    }
}

pub fn plan(r: &Resolved, verb: &Verb, common: &Common, winpkgs: &Winpkgs) -> Result<Vec<Step>> {
    if *verb == Verb::Status {
        return Ok(vec![Step::Status]);
    }
    match r.platform {
        Platform::Windows => plan_winpkgs(r, verb, common, winpkgs),
        Platform::Nixos | Platform::Darwin => plan_nh(r, verb, common),
    }
}

fn unsupported(r: &Resolved, verb: &Verb, why: &str) -> anyhow::Error {
    let target = match r.kind {
        Kind::Os => "os",
        Kind::Home => "home",
    };
    anyhow::anyhow!(
        "`stewctl {target} {}` is not available on {}: {why}",
        verb.name(),
        r.platform
    )
}

fn plan_nh(r: &Resolved, verb: &Verb, common: &Common) -> Result<Vec<Step>> {
    let (target, select) = match (r.kind, r.platform) {
        (Kind::Os, Platform::Nixos) => ("os", "-H"),
        (Kind::Os, Platform::Darwin) => ("darwin", "-H"),
        (Kind::Home, _) => ("home", "-c"),
        (Kind::Os, Platform::Windows) => unreachable!(),
    };
    let nixos = r.kind == Kind::Os && r.platform == Platform::Nixos;

    // `nh <target> <sub> <flake> -H <attr>`, plus the flags that make sense
    // for a build, plus anything after `--`.
    let nh = |sub: &str, building: bool, confirmable: bool| -> Step {
        let mut args: Vec<String> = vec![
            target.into(),
            sub.into(),
            r.flake.value.clone(),
            select.into(),
            r.attribute.value.clone(),
        ];
        if building {
            if common.update {
                args.push("--update".into());
            }
            for input in &common.update_inputs {
                args.extend(["--update-input".into(), input.clone()]);
            }
        }
        if confirmable {
            if common.ask {
                args.push("--ask".into());
            }
            if common.dry {
                args.push("--dry".into());
            }
        }
        if !verb.extra().is_empty() {
            args.push("--".into());
            args.extend(verb.extra().iter().cloned());
        }
        run("nh", args)
    };

    Ok(match verb {
        Verb::Build(_) => vec![nh("build", true, false)],
        Verb::Switch(_) => vec![nh("switch", true, true)],
        Verb::Boot(_) if nixos => vec![nh("boot", true, true)],
        Verb::Test(_) if nixos => vec![nh("test", true, true)],
        Verb::Boot(_) | Verb::Test(_) => {
            return Err(unsupported(r, verb, "only NixOS has boot entries"))
        }
        // nh compares the result with what is running after every build.
        Verb::Diff(_) => vec![nh("build", true, false)],
        Verb::Repl(_) => vec![nh("repl", false, false)],
        Verb::Generations => match (r.kind, r.platform) {
            (Kind::Os, Platform::Nixos) => vec![run("nh", ["os", "info"])],
            (Kind::Os, _) => vec![run("darwin-rebuild", ["--list-generations"])],
            (Kind::Home, _) => vec![Step::HomeGenerations],
        },
        Verb::Rollback { generation } => match (r.kind, r.platform) {
            (Kind::Os, Platform::Nixos) => {
                let mut args = vec!["os".to_string(), "rollback".into()];
                if let Some(n) = generation {
                    args.extend(["--to".into(), n.to_string()]);
                }
                vec![run("nh", args)]
            }
            (Kind::Os, _) => vec![match generation {
                Some(n) => run(
                    "sudo",
                    [
                        "darwin-rebuild".into(),
                        "--switch-generation".into(),
                        n.to_string(),
                    ],
                ),
                None => run("sudo", ["darwin-rebuild", "--rollback"]),
            }],
            (Kind::Home, _) => vec![Step::HomeRollback(*generation)],
        },
        Verb::Clean(extra) => {
            let which = if r.kind == Kind::Os { "all" } else { "user" };
            let mut args = vec!["clean".to_string(), which.into()];
            args.extend(extra.args.iter().cloned());
            vec![run("nh", args)]
        }
        Verb::Status => unreachable!(),
    })
}

fn plan_winpkgs(r: &Resolved, verb: &Verb, common: &Common, w: &Winpkgs) -> Result<Vec<Step>> {
    let (kind, select) = match r.kind {
        Kind::Os => ("system", "-System"),
        Kind::Home => ("home", "-Home"),
    };
    let flake = r.flake.value.as_str();
    let cmd = |sub: &str, rest: &[String]| -> Step {
        let mut args: Vec<String> = vec![
            select.into(),
            r.attribute.value.clone(),
            kind.into(),
            sub.into(),
        ];
        args.extend(rest.iter().cloned());
        w.step(flake, args)
    };

    // winpkgs has no update flag: the update is a step of its own, in the
    // distro, before the build.
    let mut steps = Vec::new();
    let building = matches!(verb, Verb::Build(_) | Verb::Switch(_) | Verb::Diff(_));
    if building && common.update {
        steps.push(w.step(flake, ["flake", "update"]));
    } else if building && !common.update_inputs.is_empty() {
        let mut args = vec!["flake".to_string(), "update".into()];
        args.extend(common.update_inputs.iter().cloned());
        steps.push(w.step(flake, args));
    }

    let extra = verb.extra();
    match verb {
        Verb::Build(_) => steps.push(cmd("build", extra)),
        Verb::Switch(_) if common.dry => steps.push(cmd("plan", extra)),
        Verb::Switch(_) if common.ask => {
            steps.push(cmd("plan", &[]));
            steps.push(Step::Confirm(format!(
                "Apply {kind} configuration {}?",
                r.attribute.value
            )));
            steps.push(cmd("switch", extra));
        }
        Verb::Switch(_) => steps.push(cmd("switch", extra)),
        Verb::Diff(_) => steps.push(cmd("plan", extra)),
        Verb::Boot(_) | Verb::Test(_) => {
            return Err(unsupported(r, verb, "Windows has no boot generations"))
        }
        Verb::Repl(_) => {
            return Err(unsupported(
                r,
                verb,
                "use `winpkgs shell` for a shell in the distro, then `nix repl`",
            ))
        }
        Verb::Generations => steps.push(cmd("generations", &[])),
        Verb::Rollback { generation } => {
            let n: Vec<String> = generation.iter().map(|n| n.to_string()).collect();
            steps.push(cmd("rollback", &n));
        }
        Verb::Clean(_) => steps.push(cmd("gc", extra)),
        Verb::Status => unreachable!(),
    }
    Ok(steps)
}

/// `stewctl flake <args>`.
pub fn plan_flake(platform: Platform, flake: &str, args: &[String], w: &Winpkgs) -> Step {
    match platform {
        Platform::Windows => {
            let mut all = vec!["flake".to_string()];
            all.extend(args.iter().cloned());
            w.step(flake, all)
        }
        Platform::Nixos | Platform::Darwin => {
            let mut all = vec!["flake".to_string()];
            all.extend(args.iter().cloned());
            Step::Run {
                program: "nix".into(),
                args: all,
                cwd: Some(flake.into()),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::Extra;
    use crate::identity::Sourced;

    fn resolved(kind: Kind, platform: Platform) -> Resolved {
        let attribute = match kind {
            Kind::Os => "box",
            Kind::Home => "me@box",
        };
        Resolved {
            kind,
            platform,
            flake: Sourced {
                value: "/f".into(),
                source: "test".into(),
            },
            attribute: Sourced {
                value: attribute.into(),
                source: "test".into(),
            },
        }
    }

    const W: Winpkgs = Winpkgs { cli: String::new() };

    fn lines(kind: Kind, platform: Platform, verb: Verb, common: Common) -> Vec<String> {
        let w = Winpkgs {
            cli: "cli.ps1".into(),
        };
        plan(&resolved(kind, platform), &verb, &common, &w)
            .unwrap()
            .iter()
            .map(ToString::to_string)
            .collect()
    }

    fn e() -> Extra {
        Extra::default()
    }

    #[test]
    fn nixos() {
        let c = Common::default();
        assert_eq!(
            lines(Kind::Os, Platform::Nixos, Verb::Switch(e()), c.clone()),
            ["nh os switch /f -H box"]
        );
        assert_eq!(
            lines(Kind::Os, Platform::Nixos, Verb::Boot(e()), c.clone()),
            ["nh os boot /f -H box"]
        );
        assert_eq!(
            lines(Kind::Os, Platform::Nixos, Verb::Diff(e()), c.clone()),
            ["nh os build /f -H box"]
        );
        assert_eq!(
            lines(Kind::Os, Platform::Nixos, Verb::Generations, c.clone()),
            ["nh os info"]
        );
        assert_eq!(
            lines(
                Kind::Os,
                Platform::Nixos,
                Verb::Rollback {
                    generation: Some(3)
                },
                c.clone()
            ),
            ["nh os rollback --to 3"]
        );
        assert_eq!(
            lines(Kind::Os, Platform::Nixos, Verb::Clean(e()), c),
            ["nh clean all"]
        );
    }

    #[test]
    fn darwin() {
        let c = Common::default();
        assert_eq!(
            lines(Kind::Os, Platform::Darwin, Verb::Build(e()), c.clone()),
            ["nh darwin build /f -H box"]
        );
        assert_eq!(
            lines(
                Kind::Os,
                Platform::Darwin,
                Verb::Rollback { generation: None },
                c.clone()
            ),
            ["sudo darwin-rebuild --rollback"]
        );
        let err = plan(
            &resolved(Kind::Os, Platform::Darwin),
            &Verb::Boot(e()),
            &c,
            &W,
        )
        .unwrap_err();
        assert!(err.to_string().contains("not available on darwin"), "{err}");
    }

    #[test]
    fn home_with_nh() {
        let c = Common {
            update_inputs: vec!["nixpkgs".into()],
            ask: true,
            ..Common::default()
        };
        let extra = Extra {
            args: vec!["--show-trace".into()],
        };
        assert_eq!(
            lines(Kind::Home, Platform::Nixos, Verb::Switch(extra), c.clone()),
            ["nh home switch /f -c me@box --update-input nixpkgs --ask -- --show-trace"]
        );
        assert_eq!(
            lines(Kind::Home, Platform::Darwin, Verb::Clean(e()), c.clone()),
            ["nh clean user"]
        );
        assert!(plan(
            &resolved(Kind::Home, Platform::Nixos),
            &Verb::Boot(e()),
            &c,
            &W
        )
        .is_err());
        assert_eq!(
            plan(
                &resolved(Kind::Home, Platform::Nixos),
                &Verb::Generations,
                &c,
                &W
            )
            .unwrap(),
            [Step::HomeGenerations]
        );
    }

    #[test]
    fn windows() {
        let c = Common::default();
        let base = "pwsh -NoProfile -File cli.ps1 -Flake /f";
        assert_eq!(
            lines(Kind::Os, Platform::Windows, Verb::Switch(e()), c.clone()),
            [format!("{base} -System box system switch")]
        );
        assert_eq!(
            lines(Kind::Home, Platform::Windows, Verb::Diff(e()), c.clone()),
            [format!("{base} -Home me@box home plan")]
        );
        assert_eq!(
            lines(Kind::Home, Platform::Windows, Verb::Clean(e()), c.clone()),
            [format!("{base} -Home me@box home gc")]
        );
        assert_eq!(
            lines(
                Kind::Os,
                Platform::Windows,
                Verb::Rollback {
                    generation: Some(2)
                },
                c.clone()
            ),
            [format!("{base} -System box system rollback 2")]
        );
        assert!(plan(
            &resolved(Kind::Os, Platform::Windows),
            &Verb::Boot(e()),
            &c,
            &W
        )
        .is_err());
    }

    #[test]
    fn windows_update_and_ask_are_separate_steps() {
        let c = Common {
            update: true,
            ask: true,
            ..Common::default()
        };
        let base = "pwsh -NoProfile -File cli.ps1 -Flake /f";
        assert_eq!(
            lines(Kind::Home, Platform::Windows, Verb::Switch(e()), c),
            [
                format!("{base} flake update"),
                format!("{base} -Home me@box home plan"),
                "# ask: Apply home configuration me@box?".to_string(),
                format!("{base} -Home me@box home switch"),
            ]
        );
    }

    #[test]
    fn windows_dry_switch_is_a_plan() {
        let c = Common {
            dry: true,
            ..Common::default()
        };
        assert_eq!(
            lines(Kind::Os, Platform::Windows, Verb::Switch(e()), c),
            ["pwsh -NoProfile -File cli.ps1 -Flake /f -System box system plan"]
        );
    }

    #[test]
    fn flake_runs_in_the_flake() {
        let w = Winpkgs {
            cli: "cli.ps1".into(),
        };
        let args = vec!["update".to_string(), "nixpkgs".into()];
        assert_eq!(
            plan_flake(Platform::Nixos, "/f", &args, &w).to_string(),
            "(cd /f && nix flake update nixpkgs)"
        );
        assert_eq!(
            plan_flake(Platform::Windows, r"C:\f", &args, &w).to_string(),
            r"pwsh -NoProfile -File cli.ps1 -Flake C:\f flake update nixpkgs"
        );
    }
}
