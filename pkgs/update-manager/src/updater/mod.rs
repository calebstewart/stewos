mod diff;
mod git;
mod nix;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, bail, Context, Result};

use crate::config::Config;
use crate::notify::Notifier;
use crate::state::{self, PendingUpdate, State, Summary};
use crate::tray::UpdateTray;
use crate::ApplyMode;

enum CheckOutcome {
    UpToDate,
    Updates(PendingUpdate),
}

/// What the privileged helper should do to the OS, if anything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SystemAction {
    None,
    Switch,
    Boot,
}

impl ApplyMode {
    fn system_action(self) -> SystemAction {
        match self {
            ApplyMode::Full | ApplyMode::SystemOnly => SystemAction::Switch,
            ApplyMode::HomeAndBoot => SystemAction::Boot,
            ApplyMode::HomeOnly => SystemAction::None,
        }
    }

    fn includes_home(self) -> bool {
        !matches!(self, ApplyMode::SystemOnly)
    }

    fn describe(self) -> &'static str {
        match self {
            ApplyMode::Full => "system + home",
            ApplyMode::HomeOnly => "home only",
            ApplyMode::HomeAndBoot => "home now, system on next boot",
            ApplyMode::SystemOnly => "system only",
        }
    }
}

enum ApplyOutcome {
    Applied {
        os_done: bool,
        home_done: bool,
        merge_note: Option<String>,
    },
    /// The authentication dialog was declined; nothing changed.
    Cancelled,
    /// The pending update no longer matches reality; a fresh check is needed.
    Stale { message: String },
}

pub struct Worker {
    cfg: Config,
    notifier: Notifier,
    tray: ksni::Handle<UpdateTray>,
    state: State,
}

impl Worker {
    pub fn new(cfg: Config, notifier: Notifier, tray: ksni::Handle<UpdateTray>) -> Self {
        Self {
            cfg,
            notifier,
            tray,
            state: State::Idle,
        }
    }

    fn set_state(&mut self, state: State) {
        self.state = state.clone();
        self.tray.update(move |tray| tray.set_state(state.clone()));
    }

    /// Restore "updates available" from state.json after a restart, but only
    /// if the recorded update still matches reality.
    pub fn restore(&mut self) {
        let state_file = self.cfg.state_file();
        let Some(pending) = state::load_pending(&state_file) else {
            return;
        };
        let valid = self.pending_still_valid(&pending).unwrap_or_else(|err| {
            log::warn!("could not validate persisted state: {err:#}");
            false
        });
        if valid {
            log::info!("restored pending update from {}", state_file.display());
            self.set_state(State::UpdatesAvailable(pending));
        } else {
            log::info!("persisted state is stale, discarding");
            state::clear_pending(&state_file);
        }
    }

    fn pending_still_valid(&self, p: &PendingUpdate) -> Result<bool> {
        if git::rev_parse(&self.cfg.flake, "main")? != p.main_rev {
            return Ok(false);
        }
        let system_ok = std::fs::canonicalize(self.cfg.result_system())
            .map(|path| path == Path::new(&p.system_path))
            .unwrap_or(false);
        let home_ok = std::fs::canonicalize(self.cfg.result_home())
            .map(|path| path == Path::new(&p.home_path))
            .unwrap_or(false);
        let fully_applied =
            self.os_done(Path::new(&p.system_path)) && self.home_done(Path::new(&p.home_path));
        Ok(system_ok && home_ok && !fully_applied)
    }

    pub fn check(&mut self) {
        if matches!(self.state, State::Checking | State::Applying) {
            return;
        }
        self.set_state(State::Checking);
        self.notifier.info(
            "Checking for updates",
            "Updating flake inputs and building the new system; this can take a while.",
        );

        match self.do_check() {
            Ok(CheckOutcome::UpToDate) => {
                let checked_at = chrono::Local::now().format("%H:%M").to_string();
                self.set_state(State::UpToDate { checked_at });
                self.notifier
                    .info("Up to date", "All flake inputs are current.");
            }
            Ok(CheckOutcome::Updates(pending)) => {
                if let Err(err) = state::save_pending(&self.cfg.state_file(), &pending) {
                    log::warn!("failed to persist state: {err:#}");
                }
                self.notifier
                    .updates_available(pending.summary.short(), pending.summary.breakdown());
                self.set_state(State::UpdatesAvailable(pending));
            }
            Err(err) => {
                let message = format!("{err:#}");
                log::error!("check failed: {message}");
                self.notifier.error("Update check failed", &tail(&message, 3));
                self.set_state(State::Error {
                    message: truncate(&message, 4000),
                });
            }
        }
    }

    fn do_check(&self) -> Result<CheckOutcome> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        let main_rev = git::rev_parse(flake, "main")?;
        if git::path_dirty(flake, "flake.lock")? {
            bail!(
                "flake.lock has local modifications in {}; commit or discard them first",
                flake.display()
            );
        }

        git::ensure_worktree(flake, &worktree, &self.cfg.branch)?;
        nix::flake_update(&worktree)?;

        if !git::lock_changed(&worktree)? {
            return Ok(CheckOutcome::UpToDate);
        }

        let system_path = nix::build(&self.cfg.system_installable(), &self.cfg.result_system())?;
        let home_path = nix::build(&self.cfg.home_installable(), &self.cfg.result_home())?;

        let system_diff = diff::parse(&nix::diff_closures(
            Path::new("/run/current-system"),
            &system_path,
        )?);
        let home_diff = match self.cfg.home_profile() {
            Some(profile) => diff::parse(&nix::diff_closures(&profile, &home_path)?),
            None => {
                log::warn!("no home-manager profile found; skipping home diff");
                BTreeMap::new()
            }
        };

        let summary = Summary {
            total: diff::counts(&diff::merge(&system_diff, &home_diff)),
            system: diff::counts(&system_diff),
            home: diff::counts(&home_diff),
        };

        Ok(CheckOutcome::Updates(PendingUpdate {
            summary,
            system_path: system_path.display().to_string(),
            home_path: home_path.display().to_string(),
            main_rev,
        }))
    }

    pub fn apply(&mut self, mode: ApplyMode) {
        let pending = match &self.state {
            State::UpdatesAvailable(p) => p.clone(),
            _ => {
                log::info!("apply requested but no update is pending");
                return;
            }
        };
        self.set_state(State::Applying);
        self.notifier
            .info("Applying updates", mode.describe());

        match self.do_apply(&pending, mode) {
            Ok(ApplyOutcome::Applied {
                os_done,
                home_done,
                merge_note,
            }) => {
                if os_done && home_done {
                    state::clear_pending(&self.cfg.state_file());
                    let body = if mode == ApplyMode::HomeAndBoot {
                        format!(
                            "{}. The system generation takes effect on the next boot.",
                            pending.summary.short()
                        )
                    } else {
                        pending.summary.short()
                    };
                    match merge_note {
                        None => self.notifier.info("Update applied", &body),
                        Some(note) => self.notifier.error("Update applied with a caveat", &note),
                    }
                    self.set_state(State::Idle);
                } else {
                    // Partially applied: keep the pending update around so the
                    // remaining part can be applied later (completed parts are
                    // skipped by the idempotence guards).
                    let body = if home_done {
                        "Home was updated. The system update is still pending."
                    } else {
                        "The system was updated. The home update is still pending."
                    };
                    self.notifier.info("Update partially applied", body);
                    self.set_state(State::UpdatesAvailable(pending));
                }
            }
            Ok(ApplyOutcome::Cancelled) => {
                self.notifier.info(
                    "Apply cancelled",
                    "Authentication was declined; nothing was changed.",
                );
                self.set_state(State::UpdatesAvailable(pending));
            }
            Ok(ApplyOutcome::Stale { message }) => {
                state::clear_pending(&self.cfg.state_file());
                self.notifier.error("Update no longer applies", &message);
                self.set_state(State::Idle);
            }
            Err(err) => {
                // Retryable: the idempotence guards skip whatever already
                // succeeded on the next attempt.
                let message = format!("{err:#}");
                log::error!("apply failed: {message}");
                self.notifier.error("Apply failed", &tail(&message, 3));
                self.set_state(State::UpdatesAvailable(pending));
            }
        }
    }

    fn do_apply(&self, p: &PendingUpdate, mode: ApplyMode) -> Result<ApplyOutcome> {
        let flake = &self.cfg.flake;

        if git::rev_parse(flake, "main")? != p.main_rev {
            return Ok(ApplyOutcome::Stale {
                message: "main moved since the last check; run Check for updates again."
                    .to_string(),
            });
        }
        if git::path_dirty(flake, "flake.lock")? {
            bail!(
                "flake.lock has local modifications in {}; commit or discard them first",
                flake.display()
            );
        }

        let system_path = PathBuf::from(&p.system_path);
        let home_path = PathBuf::from(&p.home_path);
        let results_ok = std::fs::canonicalize(self.cfg.result_system())
            .map(|path| path == system_path)
            .unwrap_or(false)
            && std::fs::canonicalize(self.cfg.result_home())
                .map(|path| path == home_path)
                .unwrap_or(false);
        if !results_ok {
            return Ok(ApplyOutcome::Stale {
                message: "The built update is gone; run Check for updates again.".to_string(),
            });
        }

        let mut os_done = self.os_done(&system_path);
        let mut home_done = self.home_done(&home_path);

        // The OS part first: run0 escalates through polkit, so the
        // authentication dialog comes from the session's agent and no setuid
        // binary is involved. `switch` activates now; `boot` only sets the
        // profile and boot entry. Both are skipped when already done.
        match mode.system_action() {
            SystemAction::Switch
                if std::fs::canonicalize("/run/current-system")
                    .context("resolving /run/current-system")?
                    != system_path =>
            {
                match self.run_system_helper("switch", &p.system_path)? {
                    true => os_done = true,
                    false => return Ok(ApplyOutcome::Cancelled),
                }
            }
            SystemAction::Boot if !os_done => {
                match self.run_system_helper("boot", &p.system_path)? {
                    true => os_done = true,
                    false => return Ok(ApplyOutcome::Cancelled),
                }
            }
            SystemAction::None => {}
            _ => log::info!("system part already applied, skipping"),
        }

        // Merge the lock bump back into main as soon as both parts are done
        // or about to be — and *before* home activation, because the new home
        // generation contains a new daemon binary, so activating it can
        // restart this very service, and the merge must not be lost.
        let mut merge_note = None;
        if os_done && (home_done || mode.includes_home()) {
            merge_note = self.merge_back(&p.main_rev).err().map(|err| {
                format!(
                    "The update was applied, but flake.lock could not be fast-forwarded into \
                     main ({err:#}). Merge branch '{}' manually.",
                    self.cfg.branch
                )
            });
        }

        // The home part, unprivileged, skipped if the profile already points
        // at the new generation.
        if mode.includes_home() && !home_done {
            log::info!("activating home generation: {}", p.home_path);
            let output = Command::new(home_path.join("activate"))
                .output()
                .context("failed to run home activation")?;
            if !output.status.success() {
                bail!(
                    "home activation failed (retry an apply that includes home; completed \
                     parts are skipped):\n{}",
                    String::from_utf8_lossy(&output.stderr).trim()
                );
            }
            home_done = true;
        }

        Ok(ApplyOutcome::Applied {
            os_done,
            home_done,
            merge_note,
        })
    }

    /// Has the OS part been applied? True when the system profile (which both
    /// `switch` and `boot` set) or the running system points at the new
    /// generation.
    fn os_done(&self, system_path: &Path) -> bool {
        let profile = std::fs::canonicalize("/nix/var/nix/profiles/system")
            .map(|path| path == system_path)
            .unwrap_or(false);
        let running = std::fs::canonicalize("/run/current-system")
            .map(|path| path == system_path)
            .unwrap_or(false);
        profile || running
    }

    fn home_done(&self, home_path: &Path) -> bool {
        self.cfg
            .home_profile()
            .and_then(|profile| std::fs::canonicalize(profile).ok())
            .as_deref()
            == Some(home_path)
    }

    /// Run the privileged helper via run0. Returns Ok(false) when the
    /// authentication dialog was declined.
    fn run_system_helper(&self, action: &str, system_path: &str) -> Result<bool> {
        let helper = apply_helper()?;
        log::info!("running system {action} via run0: {system_path}");
        let output = Command::new("run0")
            .arg("--pipe")
            .arg(helper)
            .arg(action)
            .arg(system_path)
            .output()
            .context("failed to run run0")?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if auth_declined(&stderr) {
                log::warn!("run0 authentication declined: {}", stderr.trim());
                return Ok(false);
            }
            bail!("system {action} failed:\n{}", stderr.trim());
        }
        Ok(true)
    }

    fn merge_back(&self, main_rev: &str) -> Result<()> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        if git::lock_changed(&worktree)? {
            git::commit_lock(&worktree)?;
        }
        // Already merged by an earlier, partially completed apply.
        if git::rev_parse(flake, "main")? == git::rev_parse(flake, &self.cfg.branch)? {
            return Ok(());
        }
        if git::path_dirty(flake, "flake.lock")? {
            bail!("flake.lock was modified locally during the apply");
        }
        if git::rev_parse(flake, "main")? != main_rev {
            bail!("main moved during the apply");
        }
        git::merge_back(flake, &self.cfg.branch)
    }
}

/// Did run0 fail because authorization was declined or the dialog dismissed,
/// rather than because the switch itself failed?
fn auth_declined(stderr: &str) -> bool {
    let s = stderr.to_lowercase();
    s.contains("access denied") || s.contains("authentication") || s.contains("not authorized")
}

fn apply_helper() -> Result<PathBuf> {
    if let Ok(helper) = std::env::var("STEWOS_APPLY_HELPER") {
        return Ok(PathBuf::from(helper));
    }
    let exe = std::env::current_exe().context("resolving own executable path")?;
    exe.parent()
        .and_then(Path::parent)
        .map(|prefix| prefix.join("libexec/stewos-apply-system"))
        .filter(|helper| helper.exists())
        .ok_or_else(|| {
            anyhow!("stewos-apply-system helper not found; set STEWOS_APPLY_HELPER for dev runs")
        })
}

/// Last `lines` lines of a message, for notification bodies.
fn tail(message: &str, lines: usize) -> String {
    let all: Vec<&str> = message.lines().collect();
    let start = all.len().saturating_sub(lines);
    all[start..].join("\n")
}

fn truncate(message: &str, max: usize) -> String {
    if message.len() <= max {
        message.to_string()
    } else {
        let mut end = max;
        while !message.is_char_boundary(end) {
            end -= 1;
        }
        format!("{}\u{2026}", &message[..end])
    }
}
