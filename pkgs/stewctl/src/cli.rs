//! The command line: `stewctl os <verb>`, `stewctl home <verb>`, `stewctl
//! flake <args>`. Every verb is a subcommand of its target, as in nh; there is
//! no command that applies both configurations.

use clap::{Args, Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(
    version,
    about = "Build and switch this machine's StewOS configurations",
    long_about = "Build and switch this machine's StewOS configurations.\n\n\
        One command on NixOS, macOS and Windows. `os` is the system \
        configuration and `home` is this user's; each verb acts on exactly one \
        of them. The work is done by nh on NixOS and macOS and by winpkgs on \
        Windows -- stewctl decides which configuration and which engine."
)]
pub struct Cli {
    #[command(subcommand)]
    pub target: Target,
}

#[derive(Subcommand, Debug)]
pub enum Target {
    /// The system configuration: NixOS, nix-darwin or a winpkgs system.
    #[command(visible_alias = "system")]
    Os {
        #[command(subcommand)]
        verb: Verb,
        #[command(flatten)]
        common: Common,
        /// The attribute under nixosConfigurations, darwinConfigurations or
        /// windowsConfigurations.
        #[arg(short = 'H', long, global = true, value_name = "NAME")]
        host: Option<String>,
    },
    /// This user's home configuration.
    Home {
        #[command(subcommand)]
        verb: Verb,
        #[command(flatten)]
        common: Common,
        /// The attribute under homeConfigurations or
        /// windowsHomeConfigurations, `user@host`.
        #[arg(
            short = 'c',
            long,
            visible_alias = "home",
            global = true,
            value_name = "NAME"
        )]
        configuration: Option<String>,
    },
    /// Run `nix flake <args>` in the flake's directory (in the WSL distro, on
    /// Windows): `stewctl flake update`, `stewctl flake update nixpkgs`, ...
    Flake {
        #[command(flatten)]
        common: FlakeOnly,
        #[arg(trailing_var_arg = true, allow_hyphen_values = true, required = true)]
        args: Vec<String>,
    },
}

/// Flags every verb of `os` and `home` accepts.
#[derive(Args, Debug, Default, Clone)]
pub struct Common {
    /// The flake. Defaults to what the configuration recorded, then
    /// $STEWCTL_FLAKE, $NH_FLAKE and ~/git/stewos.
    #[arg(short = 'f', long, global = true, value_name = "PATH")]
    pub flake: Option<String>,

    /// Update every flake input first.
    #[arg(short = 'u', long, global = true)]
    pub update: bool,

    /// Update this flake input first (repeatable).
    #[arg(
        short = 'U',
        long = "update-input",
        global = true,
        value_name = "INPUT"
    )]
    pub update_inputs: Vec<String>,

    /// Show what would change and ask before applying it.
    #[arg(short = 'a', long, global = true)]
    pub ask: bool,

    /// Show what would change and apply nothing.
    #[arg(short = 'n', long, global = true)]
    pub dry: bool,

    /// Print the commands instead of running them.
    #[arg(long, global = true)]
    pub print: bool,
}

#[derive(Args, Debug, Default, Clone)]
pub struct FlakeOnly {
    /// The flake. Defaults as for `os` and `home`.
    #[arg(short = 'f', long, value_name = "PATH")]
    pub flake: Option<String>,

    /// Print the command instead of running it.
    #[arg(long)]
    pub print: bool,
}

#[derive(Subcommand, Debug, Clone, PartialEq, Eq)]
pub enum Verb {
    /// Build the configuration and show what changed; activate nothing.
    Build(Extra),
    /// Build, activate, and make it the current generation.
    Switch(Extra),
    /// Build and make it the generation the next boot starts (NixOS only).
    Boot(Extra),
    /// Build and activate without adding a boot entry (NixOS only).
    Test(Extra),
    /// Show what a switch would change.
    #[command(visible_alias = "plan")]
    Diff(Extra),
    /// List the generations and which one is current.
    #[command(visible_alias = "info")]
    Generations,
    /// Go back to generation N, by default the one before the current.
    Rollback {
        #[arg(value_name = "N")]
        generation: Option<u32>,
    },
    /// Delete old generations and collect garbage.
    #[command(visible_alias = "gc")]
    Clean(Extra),
    /// Open a Nix REPL on the configuration.
    Repl(Extra),
    /// Show which flake and configuration this resolves to, and why.
    Status,
}

/// Arguments after `--`, handed to the engine untouched.
#[derive(Args, Debug, Default, Clone, PartialEq, Eq)]
pub struct Extra {
    #[arg(last = true, value_name = "ENGINE ARGS")]
    pub args: Vec<String>,
}

impl Verb {
    pub fn name(&self) -> &'static str {
        match self {
            Verb::Build(_) => "build",
            Verb::Switch(_) => "switch",
            Verb::Boot(_) => "boot",
            Verb::Test(_) => "test",
            Verb::Diff(_) => "diff",
            Verb::Generations => "generations",
            Verb::Rollback { .. } => "rollback",
            Verb::Clean(_) => "clean",
            Verb::Repl(_) => "repl",
            Verb::Status => "status",
        }
    }

    pub fn extra(&self) -> &[String] {
        match self {
            Verb::Build(e)
            | Verb::Switch(e)
            | Verb::Boot(e)
            | Verb::Test(e)
            | Verb::Diff(e)
            | Verb::Clean(e)
            | Verb::Repl(e) => &e.args,
            _ => &[],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn cli_is_well_formed() {
        Cli::command().debug_assert();
    }

    #[test]
    fn a_bare_verb_is_refused() {
        assert!(Cli::try_parse_from(["stewctl", "switch"]).is_err());
    }

    #[test]
    fn flags_go_before_or_after_the_verb() {
        let before = Cli::try_parse_from(["stewctl", "os", "-H", "x", "switch"]).unwrap();
        let after = Cli::try_parse_from(["stewctl", "os", "switch", "-H", "x", "-u"]).unwrap();
        for cli in [before, after] {
            let Target::Os { host, .. } = cli.target else {
                panic!("not os")
            };
            assert_eq!(host.as_deref(), Some("x"));
        }
    }

    #[test]
    fn system_is_os() {
        let cli = Cli::try_parse_from(["stewctl", "system", "build"]).unwrap();
        assert!(matches!(cli.target, Target::Os { .. }));
    }

    #[test]
    fn extra_arguments_follow_a_double_dash() {
        let cli = Cli::try_parse_from(["stewctl", "home", "switch", "--", "--show-trace"]).unwrap();
        let Target::Home { verb, .. } = cli.target else {
            panic!("not home")
        };
        assert_eq!(verb.extra(), ["--show-trace"]);
    }

    #[test]
    fn flake_takes_everything() {
        let cli =
            Cli::try_parse_from(["stewctl", "flake", "update", "--commit-lock-file"]).unwrap();
        let Target::Flake { args, .. } = cli.target else {
            panic!("not flake")
        };
        assert_eq!(args, ["update", "--commit-lock-file"]);
    }
}
