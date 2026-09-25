//! Which flake, and which configuration in it, this machine is.
//!
//! Each configuration writes down its own identity -- `os.json` from the
//! system configuration, `home.json` from the home one -- so stewctl does not
//! have to guess from the hostname. The guess is still there as the last
//! fallback, and `stewctl <target> status` says where every value came from.

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::fmt;
use std::path::{Path, PathBuf};

/// What a configuration records about itself.
#[derive(Deserialize, Debug, Default, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Identity {
    pub flake: Option<String>,
    pub platform: Option<Platform>,
    pub attribute: Option<String>,
}

#[derive(Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Nixos,
    Darwin,
    Windows,
}

impl fmt::Display for Platform {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Platform::Nixos => "nixos",
            Platform::Darwin => "darwin",
            Platform::Windows => "windows",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Os,
    Home,
}

/// A resolved value and where it came from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sourced {
    pub value: String,
    pub source: String,
}

impl Sourced {
    fn new(value: impl Into<String>, source: impl Into<String>) -> Self {
        Sourced {
            value: value.into(),
            source: source.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub kind: Kind,
    pub platform: Platform,
    pub flake: Sourced,
    pub attribute: Sourced,
}

/// Everything resolution reads from the machine, gathered up front so that
/// resolution itself is a pure function the tests can drive.
#[derive(Debug, Clone, Default)]
pub struct Host {
    /// The platform stewctl was built for; the machine's own answer when no
    /// `os.json` says otherwise.
    pub native: Option<Platform>,
    pub windows: bool,
    pub vars: HashMap<String, String>,
    pub os: Option<(PathBuf, Identity)>,
    pub home: Option<(PathBuf, Identity)>,
    pub hostname: Option<String>,
    pub user_home: Option<PathBuf>,
}

impl Host {
    pub fn detect() -> Result<Self> {
        let windows = cfg!(windows);
        let vars: HashMap<String, String> = std::env::vars().collect();
        let user_home = if windows {
            vars.get("USERPROFILE").map(PathBuf::from)
        } else {
            vars.get("HOME").map(PathBuf::from)
        };

        let native = if windows {
            Some(Platform::Windows)
        } else if cfg!(target_os = "macos") {
            Some(Platform::Darwin)
        } else if Path::new("/etc/NIXOS").exists() {
            Some(Platform::Nixos)
        } else {
            None
        };

        let os_path = if windows {
            vars.get("ProgramData")
                .or_else(|| vars.get("PROGRAMDATA"))
                .map(|d| Path::new(d).join("stewctl").join("os.json"))
        } else {
            Some(PathBuf::from("/etc/stewctl/os.json"))
        };
        let config_home = vars
            .get("XDG_CONFIG_HOME")
            .filter(|d| !d.is_empty())
            .map(PathBuf::from)
            .or_else(|| user_home.as_ref().map(|h| h.join(".config")));
        let home_path = config_home.map(|d| d.join("stewctl").join("home.json"));

        let hostname = if windows {
            vars.get("COMPUTERNAME").map(|n| n.to_lowercase())
        } else {
            unix_hostname()
        };

        Ok(Host {
            native,
            windows,
            os: os_path.map(read_identity).transpose()?.flatten(),
            home: home_path.map(read_identity).transpose()?.flatten(),
            vars,
            hostname,
            user_home,
        })
    }

    fn var(&self, name: &str) -> Option<&str> {
        self.vars
            .get(name)
            .map(String::as_str)
            .filter(|v| !v.is_empty())
    }

    fn username(&self) -> Option<&str> {
        if self.windows {
            self.var("USERNAME")
        } else {
            self.var("USER").or_else(|| self.var("LOGNAME"))
        }
    }

    /// The platform of the system configuration.
    pub fn platform(&self) -> Result<Platform> {
        if let Some(p) = self.os.as_ref().and_then(|(_, id)| id.platform) {
            return Ok(p);
        }
        match self.native {
            Some(p) => Ok(p),
            None => bail!(
                "this machine is not NixOS, nix-darwin or Windows, and no os.json says what it is"
            ),
        }
    }

    /// The flake: `flag`, $STEWCTL_FLAKE, what the configuration recorded
    /// (a home without one borrows the machine's), $NH_FLAKE, ~/git/stewos.
    pub fn flake(&self, kind: Kind, flag: Option<&str>) -> Result<Sourced> {
        let own = match kind {
            Kind::Os => self.os.as_ref(),
            Kind::Home => self.home.as_ref(),
        };
        Ok(if let Some(f) = flag {
            Sourced::new(f, "--flake")
        } else if let Some(f) = self.var("STEWCTL_FLAKE") {
            Sourced::new(f, "$STEWCTL_FLAKE")
        } else if let Some((path, f)) = own.and_then(|(p, id)| Some((p, id.flake.as_ref()?))) {
            Sourced::new(f, path.display().to_string())
        } else if let Some((path, f)) = self
            .os
            .as_ref()
            .and_then(|(p, id)| Some((p, id.flake.as_ref()?)))
        {
            Sourced::new(f, path.display().to_string())
        } else if let Some(f) = self.var("NH_FLAKE") {
            Sourced::new(f, "$NH_FLAKE")
        } else if let Some(home) = &self.user_home {
            Sourced::new(
                home.join("git").join("stewos").display().to_string(),
                "default",
            )
        } else {
            bail!("no flake: pass --flake or set STEWCTL_FLAKE");
        })
    }

    pub fn resolve(
        &self,
        kind: Kind,
        flake: Option<&str>,
        attribute: Option<&str>,
    ) -> Result<Resolved> {
        // A winpkgs distro does not import the StewOS modules, so it has no
        // os.json. Guessing from its hostname would find
        // nixosConfigurations.<host> -- the distro -- and rebuild it behind
        // the Windows side's back.
        if !self.windows && self.os.is_none() {
            if let Some(distro) = self.var("WSL_DISTRO_NAME") {
                bail!(
                    "this is the WSL distro {distro}, which is not a StewOS host: \
                     its Windows machine manages it. Run stewctl from Windows."
                );
            }
        }

        let platform = match kind {
            Kind::Os => self.platform()?,
            // A home's engine follows the operating system, not the system
            // configuration: `nh home` on NixOS and macOS alike.
            Kind::Home if self.windows => Platform::Windows,
            Kind::Home => self.native.unwrap_or(Platform::Nixos),
        };

        let flake = self.flake(kind, flake)?;

        let host = || -> Result<Sourced> {
            if let Some(a) = self.var("STEWCTL_HOST") {
                Ok(Sourced::new(a, "$STEWCTL_HOST"))
            } else if let Some((path, a)) = self
                .os
                .as_ref()
                .and_then(|(p, id)| Some((p, id.attribute.as_ref()?)))
            {
                Ok(Sourced::new(a, path.display().to_string()))
            } else if let Some(h) = &self.hostname {
                Ok(Sourced::new(h, "hostname"))
            } else {
                bail!("cannot tell which host this is: pass --host or set STEWCTL_HOST")
            }
        };

        let attribute = match (kind, attribute) {
            (Kind::Os, Some(a)) => Sourced::new(a, "--host"),
            (Kind::Home, Some(a)) => Sourced::new(a, "--configuration"),
            (Kind::Os, None) => host()?,
            (Kind::Home, None) => {
                if let Some(a) = self.var("STEWCTL_HOME") {
                    Sourced::new(a, "$STEWCTL_HOME")
                } else if let Some((path, a)) = self
                    .home
                    .as_ref()
                    .and_then(|(p, id)| Some((p, id.attribute.as_ref()?)))
                {
                    Sourced::new(a, path.display().to_string())
                } else {
                    let user = self
                        .username()
                        .context("cannot tell who you are: pass --configuration user@host")?;
                    let host = host()?;
                    Sourced::new(
                        format!("{user}@{}", host.value),
                        format!("user@{}", host.source),
                    )
                }
            }
        };

        Ok(Resolved {
            kind,
            platform,
            flake,
            attribute,
        })
    }
}

fn read_identity(path: PathBuf) -> Result<Option<(PathBuf, Identity)>> {
    match std::fs::read_to_string(&path) {
        Ok(text) => {
            let id = serde_json::from_str(&text)
                .with_context(|| format!("{} is not a stewctl identity", path.display()))?;
            Ok(Some((path, id)))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e).with_context(|| format!("reading {}", path.display())),
    }
}

#[cfg(unix)]
fn unix_hostname() -> Option<String> {
    // The short name, as nh uses it: macOS's `hostname` is often fully
    // qualified.
    let out = std::process::Command::new("hostname").output().ok()?;
    let name = String::from_utf8(out.stdout).ok()?;
    let short = name.trim().split('.').next()?.to_string();
    (!short.is_empty()).then_some(short)
}

#[cfg(not(unix))]
fn unix_hostname() -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host(vars: &[(&str, &str)]) -> Host {
        Host {
            native: Some(Platform::Nixos),
            windows: false,
            vars: vars
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
            hostname: Some("framework16".into()),
            user_home: Some("/home/caleb".into()),
            ..Host::default()
        }
    }

    fn id(flake: Option<&str>, platform: Option<Platform>, attribute: Option<&str>) -> Identity {
        Identity {
            flake: flake.map(Into::into),
            platform,
            attribute: attribute.map(Into::into),
        }
    }

    #[test]
    fn falls_back_to_the_hostname_and_the_default_flake() {
        let r = host(&[("USER", "caleb")])
            .resolve(Kind::Home, None, None)
            .unwrap();
        assert_eq!(r.attribute.value, "caleb@framework16");
        assert_eq!(r.attribute.source, "user@hostname");
        assert_eq!(r.flake.value, "/home/caleb/git/stewos");
        assert_eq!(r.flake.source, "default");
    }

    #[test]
    fn a_recorded_identity_beats_the_guess() {
        let mut h = host(&[("USER", "caleb"), ("NH_FLAKE", "/nh")]);
        h.os = Some((
            "/etc/stewctl/os.json".into(),
            id(
                Some("/srv/stewos"),
                Some(Platform::Nixos),
                Some("framework-desktop"),
            ),
        ));
        h.home = Some((
            "/home/caleb/.config/stewctl/home.json".into(),
            id(None, None, Some("me@there")),
        ));

        let os = h.resolve(Kind::Os, None, None).unwrap();
        assert_eq!(os.attribute.value, "framework-desktop");
        assert_eq!(os.flake.value, "/srv/stewos");

        // The home recorded no flake of its own, so it borrows the machine's.
        let home = h.resolve(Kind::Home, None, None).unwrap();
        assert_eq!(home.attribute.value, "me@there");
        assert_eq!(home.flake.value, "/srv/stewos");
        assert_eq!(home.flake.source, "/etc/stewctl/os.json");
    }

    #[test]
    fn nh_flake_is_honoured_before_the_default() {
        let r = host(&[("NH_FLAKE", "/nh")])
            .resolve(Kind::Os, None, None)
            .unwrap();
        assert_eq!(r.flake.value, "/nh");
    }

    #[test]
    fn flags_and_environment_win() {
        let mut h = host(&[("STEWCTL_FLAKE", "/env"), ("STEWCTL_HOST", "envhost")]);
        h.os = Some((
            "/etc/stewctl/os.json".into(),
            id(Some("/file"), None, Some("filehost")),
        ));
        let r = h.resolve(Kind::Os, None, None).unwrap();
        assert_eq!(
            (r.flake.value.as_str(), r.attribute.value.as_str()),
            ("/env", "envhost")
        );
        let r = h
            .resolve(Kind::Os, Some("/flag"), Some("flaghost"))
            .unwrap();
        assert_eq!(
            (r.flake.value.as_str(), r.attribute.value.as_str()),
            ("/flag", "flaghost")
        );
    }

    #[test]
    fn the_recorded_platform_wins() {
        let mut h = host(&[]);
        h.native = None;
        assert!(h.resolve(Kind::Os, None, None).is_err());
        h.os = Some((
            "/etc/stewctl/os.json".into(),
            id(None, Some(Platform::Darwin), None),
        ));
        assert_eq!(
            h.resolve(Kind::Os, None, None).unwrap().platform,
            Platform::Darwin
        );
    }

    #[test]
    fn a_wsl_distro_is_refused() {
        let h = host(&[("WSL_DISTRO_NAME", "NixOS")]);
        let err = h.resolve(Kind::Os, None, None).unwrap_err().to_string();
        assert!(err.contains("Run stewctl from Windows"), "{err}");
    }

    #[test]
    fn identity_files_parse() {
        let parsed: Identity = serde_json::from_str(
            r#"{"flake":"/home/caleb/git/stewos","platform":"nixos","attribute":"framework16"}"#,
        )
        .unwrap();
        assert_eq!(
            parsed,
            id(
                Some("/home/caleb/git/stewos"),
                Some(Platform::Nixos),
                Some("framework16")
            )
        );
        let partial: Identity =
            serde_json::from_str(r#"{"attribute":"caleb@framework16"}"#).unwrap();
        assert_eq!(partial.flake, None);
    }
}
