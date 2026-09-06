mod diff;
mod git;
mod inputs;
mod nix;
mod plan;
mod progress;
mod roots;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use stewos_update_manager::{BuildPlan, PackageChange, Scope};

use crate::cancel::{CancelReason, Canceller};
use crate::config::Config;
use crate::notify::{Notifier, ProgressNotification};
use crate::review::Reviewer;
use crate::state::{self, PendingUpdate, Progress, State, Summary};
use crate::tray::UpdateTray;
use crate::troubleshoot::{self, Action, ErrorReport, Operation};
use crate::ApplyMode;

/// Strip SGR escapes from one line of nix output. Nix colours its diffs and
/// its lock-file log, and both parsers want the text underneath.
///
/// Nix omits colour when stderr is not a tty, which it is not under
/// `Command::output()`, but a future nix could change its mind and the cost of
/// being wrong is a parser that silently matches nothing.
pub(super) fn strip_ansi(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&n) = chars.peek() {
                    chars.next();
                    if n.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

enum CheckOutcome {
    UpToDate,
    /// The lock moved, but to exactly where the pending update already is.
    /// The pending update -- built or not -- is left alone.
    Unchanged,
    Updates(PendingUpdate),
}

enum BuildOutcome {
    Built(PendingUpdate),
    Cancelled(CancelReason),
    /// The pending update no longer matches reality; a fresh check is needed.
    Stale { message: String },
}

/// What the privileged helper should do to the OS, if anything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SystemAction {
    None,
    Switch,
    Boot,
}

/// `ApplyMode` now lives in the shared library (the dialog needs it too), and
/// an inherent impl has to be in the defining crate -- so what is private to
/// the updater hangs off an extension trait instead. `describe()` moved to the
/// library with the type.
trait ApplyModeExt {
    fn system_action(self) -> SystemAction;
    fn includes_home(self) -> bool;
}

impl ApplyModeExt for ApplyMode {
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
}

/// Turn one parsed diff into the wire rows the dialog renders.
fn flatten(
    diffs: &BTreeMap<String, diff::PackageDiff>,
    scope: Scope,
) -> impl Iterator<Item = PackageChange> + '_ {
    diffs.iter().map(move |(name, d)| PackageChange {
        name: name.clone(),
        change: d.change,
        before: d.before.clone(),
        after: d.after.clone(),
        size: d.size.clone(),
        scope,
    })
}

/// What a `state.json` left by a previous daemon means on startup.
enum Persisted {
    /// Still pending; restore it.
    Pending,
    /// Both parts are what the system runs: the previous daemon finished the
    /// apply but was stopped before it could report it.
    Applied,
    /// Does not match reality any more; discard it.
    Stale,
}

enum ApplyOutcome {
    Applied {
        os_done: bool,
        home_done: bool,
        /// Things that went wrong without undoing the apply: a switch that
        /// finished with failed units, a lock bump that could not be merged.
        caveats: Vec<String>,
    },
    /// The authentication dialog was declined; nothing changed.
    Cancelled,
    /// The pending update no longer matches reality; a fresh check is needed.
    Stale { message: String },
}

fn push_state(tray: &ksni::Handle<UpdateTray>, state: State) {
    tray.update(move |tray| tray.set_state(state.clone()));
}

/// Pushes a build's progress to the tray and the progress notification,
/// throttled to a change of a whole percent and at most once a second.
///
/// The throttle is not cosmetic: a five-path build emits close to seven
/// thousand log records, and every `tray.update` makes ksni re-hash every
/// pixmap it serves. Boundaries (the start, between the two builds, the end)
/// are reported unconditionally so the display never lags at a milestone.
struct Reporter<'a> {
    tray: &'a ksni::Handle<UpdateTray>,
    notification: Option<ProgressNotification>,
    last: Instant,
    last_pct: Option<u8>,
}

impl<'a> Reporter<'a> {
    fn new(
        tray: &'a ksni::Handle<UpdateTray>,
        notifier: &Notifier,
        first: &Progress,
        quiet: bool,
    ) -> Self {
        push_state(tray, State::Building(first.clone()));
        Self {
            tray,
            notification: if quiet {
                None
            } else {
                notifier.progress(first)
            },
            last: Instant::now(),
            last_pct: Some(first.percent()),
        }
    }

    fn report(&mut self, progress: &Progress, force: bool) {
        let pct = progress.percent();
        if !force && (self.last_pct == Some(pct) || self.last.elapsed() < Duration::from_secs(1))
        {
            return;
        }
        push_state(self.tray, State::Building(progress.clone()));
        if let Some(notification) = &mut self.notification {
            notification.update(progress);
        }
        self.last = Instant::now();
        self.last_pct = Some(pct);
    }

    /// Take the progress notification down. Whatever follows -- ready to
    /// apply, cancelled, failed -- is its own notification.
    fn finish(self) {
        if let Some(notification) = self.notification {
            notification.close();
        }
    }
}

/// What asked for an operation. A scheduled one is quiet: it reports what is
/// new, never that it ran.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Trigger {
    Manual,
    Scheduled,
}

/// The worker loop's timers: the periodic check, if one is configured, and
/// the re-poll of a blocked checkout so the tray clears itself after a
/// commit. Plain arithmetic over `Instant`s, so it can be tested.
///
/// Kept in the daemon rather than in a systemd timer on purpose. The schedule
/// has to know the daemon's state -- never during a build or apply, not while
/// blocked, and reset by a manual check -- and the daemon has no control
/// socket a timer could poke; its lifetime already is the session.
#[derive(Debug, Clone)]
struct Schedule {
    interval: Option<Duration>,
    next_check: Option<Instant>,
    blocked_poll: Option<Instant>,
}

impl Schedule {
    const BLOCKED_POLL: Duration = Duration::from_secs(30);
    /// The longest the loop sleeps with nothing due. Bounded because
    /// `Instant + Duration::MAX` panics, and a spurious wake-up costs nothing.
    const IDLE: Duration = Duration::from_secs(3600);

    fn new(interval: Option<Duration>, now: Instant) -> Self {
        let mut schedule = Self {
            interval,
            next_check: None,
            blocked_poll: None,
        };
        schedule.arm_check(now);
        schedule
    }

    /// Start the interval over, from now. Called after every check, whoever
    /// asked for it, so a manual check pushes the next scheduled one out.
    fn arm_check(&mut self, now: Instant) {
        self.next_check = self.interval.map(|interval| now + interval);
    }

    fn check_due(&self, now: Instant) -> bool {
        self.next_check.is_some_and(|at| at <= now)
    }

    fn arm_blocked_poll(&mut self, now: Instant) {
        self.blocked_poll = Some(now + Self::BLOCKED_POLL);
    }

    fn clear_blocked_poll(&mut self) {
        self.blocked_poll = None;
    }

    fn blocked_poll_due(&self, now: Instant) -> bool {
        self.blocked_poll.is_some_and(|at| at <= now)
    }

    /// How long the loop may sleep before something is due.
    fn wakeup(&self, now: Instant) -> Duration {
        [self.next_check, self.blocked_poll]
            .into_iter()
            .flatten()
            .map(|at| at.saturating_duration_since(now))
            .min()
            .unwrap_or(Self::IDLE)
            .min(Self::IDLE)
    }
}

pub struct Worker {
    cfg: Config,
    notifier: Notifier,
    tray: ksni::Handle<UpdateTray>,
    state: State,
    schedule: Schedule,
    /// The last failure, whichever operation it came from. Deliberately not
    /// persisted alongside `PendingUpdate`: the report quotes this boot's
    /// journal, which would not survive a restart to describe.
    last_error: Option<ErrorReport>,
    /// None when no dialog binary was found, in which case the tray also omits
    /// the Review entry.
    review: Option<Reviewer>,
    /// Shared with the tray, which is the only thing that can stop a build.
    canceller: Canceller,
}

impl Worker {
    pub fn new(
        cfg: Config,
        notifier: Notifier,
        tray: ksni::Handle<UpdateTray>,
        review: Option<Reviewer>,
        canceller: Canceller,
    ) -> Self {
        let schedule = Schedule::new(cfg.check_interval, Instant::now());
        Self {
            cfg,
            notifier,
            tray,
            state: State::Idle,
            schedule,
            last_error: None,
            review,
            canceller,
        }
    }

    /// How long the main loop may wait for a command before calling
    /// [`Worker::tick`].
    pub fn next_wakeup(&self) -> Duration {
        self.schedule.wakeup(Instant::now())
    }

    /// The timers fired. A blocked checkout is re-inspected; a due scheduled
    /// check runs unless something else is going on, in which case it is
    /// simply pushed out by one interval.
    pub fn tick(&mut self) {
        let now = Instant::now();
        if self.schedule.blocked_poll_due(now) {
            self.schedule.clear_blocked_poll();
            self.refresh_blocked();
        }
        if self.schedule.check_due(now) {
            if self.busy() || matches!(self.state, State::Blocked { .. }) {
                self.schedule.arm_check(now);
            } else {
                self.check(Trigger::Scheduled);
            }
        }
    }

    fn blocked(&self) -> Result<Option<String>> {
        let porcelain = git::status_porcelain(&self.cfg.flake)?;
        Ok(git::blocked_reason(&porcelain, &self.cfg.flake))
    }

    /// Notified on the transition only: a Check click while blocked re-polls
    /// without nagging, and so does the timer.
    fn enter_blocked(&mut self, reason: String) {
        let already = matches!(self.state, State::Blocked { .. });
        if !already {
            self.notifier.blocked(&reason);
        }
        self.set_state(State::Blocked { reason });
        self.schedule.arm_blocked_poll(Instant::now());
    }

    /// Re-inspect the checkout. True when it is (still) blocked, in which case
    /// the state has been set and the caller has nothing more to do. Leaving
    /// the blocked state goes through [`Worker::restore`], which puts the
    /// persisted pending update back if it is still valid.
    fn refresh_blocked(&mut self) -> bool {
        match self.blocked() {
            Ok(Some(reason)) => {
                self.enter_blocked(reason);
                true
            }
            Ok(None) => {
                if matches!(self.state, State::Blocked { .. }) {
                    self.schedule.clear_blocked_poll();
                    self.set_state(State::Idle);
                    self.restore();
                }
                false
            }
            Err(err) => {
                // Not blocked for want of an answer; whatever is wrong with
                // git will surface from the operation itself.
                log::warn!("could not inspect the checkout: {err:#}");
                false
            }
        }
    }

    /// Open the review window on the pending update.
    ///
    /// Read-only: the dialog's answer comes back as a `Command::Build` or
    /// `Command::Apply` like any other and goes through the same guards as a
    /// tray click.
    pub fn review(&self) {
        let State::UpdatesAvailable(pending) = &self.state else {
            log::info!("review requested but no update is pending");
            return;
        };
        let Some(reviewer) = &self.review else {
            log::info!("review requested but no dialog is configured");
            return;
        };
        if let Err(err) = reviewer.open(&pending.review_request(&self.cfg.host)) {
            log::error!("review dialog failed: {err:#}");
            // Plain error(), like troubleshoot(): offering to troubleshoot the
            // review window is not a useful thing to do here.
            self.notifier
                .error("Could not open the review window", &format!("{err:#}"));
        }
    }

    fn set_state(&mut self, state: State) {
        self.state = state.clone();
        push_state(&self.tray, state);
    }

    /// Record (or clear) the failure the troubleshooting entries work from. The
    /// tray is only told whether one exists; the report stays here.
    fn set_last_error(&mut self, report: Option<ErrorReport>) {
        let has_error = report.is_some();
        self.last_error = report;
        self.tray.update(move |tray| tray.set_has_error(has_error));
    }

    fn busy(&self) -> bool {
        matches!(
            self.state,
            State::Checking | State::Building(_) | State::Applying
        )
    }

    /// Restore "updates available" from state.json after a restart, but only
    /// if the recorded update still matches reality.
    pub fn restore(&mut self) {
        // Before the state file is even read: the validation below discards
        // it on failure, and a dirty checkout is no reason to lose a pending
        // update. It waits, blocked, until the checkout is clean.
        match self.blocked() {
            Ok(Some(reason)) => {
                self.enter_blocked(reason);
                return;
            }
            Ok(None) => {}
            Err(err) => log::warn!("could not inspect the checkout: {err:#}"),
        }

        let state_file = self.cfg.state_file();
        let Some(pending) = state::load_pending(&state_file) else {
            return;
        };
        let persisted = self.classify_persisted(&pending).unwrap_or_else(|err| {
            log::warn!("could not validate persisted state: {err:#}");
            Persisted::Stale
        });
        match persisted {
            Persisted::Pending => {
                log::info!("restored pending update from {}", state_file.display());
                self.set_state(State::UpdatesAvailable(pending));
            }
            // The apply finished, but the daemon running it was stopped by
            // the home activation (the new generation restarts this unit)
            // before it could say so. Say so now: without this the user
            // sees the tray go quiet and nothing else.
            Persisted::Applied => {
                log::info!("pending update was applied before this restart");
                state::clear_pending(&state_file);
                self.notifier
                    .info("Update applied", &pending.summary.short());
            }
            Persisted::Stale => {
                log::info!("persisted state is stale, discarding");
                state::clear_pending(&state_file);
            }
        }
    }

    fn classify_persisted(&self, p: &PendingUpdate) -> Result<Persisted> {
        // Applied is checked before `main_rev`: a finished apply has merged
        // the lock bump, so `main` has moved on purpose.
        if let (Some(system_path), Some(home_path)) = (&p.system_path, &p.home_path) {
            if self.os_done(Path::new(system_path)) && self.home_done(Path::new(home_path)) {
                return Ok(Persisted::Applied);
            }
        }
        if git::rev_parse(&self.cfg.flake, "main")? != p.main_rev {
            return Ok(Persisted::Stale);
        }
        let pending = match (&p.system_path, &p.home_path) {
            (Some(system_path), Some(home_path)) => {
                let system_ok = std::fs::canonicalize(self.cfg.result_system())
                    .map(|path| path == Path::new(system_path))
                    .unwrap_or(false);
                let home_ok = std::fs::canonicalize(self.cfg.result_home())
                    .map(|path| path == Path::new(home_path))
                    .unwrap_or(false);
                system_ok && home_ok
            }
            // Unbuilt: the updated lock exists only in the worktree. If it is
            // gone, the honest answer is a fresh check -- not another `flake
            // update`, which could lock newer revisions than the ones the
            // user reviewed.
            _ => {
                let worktree = self.cfg.worktree();
                worktree.join("flake.lock").is_file()
                    && git::hash_object(&worktree, "flake.lock")? == p.lock_hash
            }
        };
        Ok(if pending {
            Persisted::Pending
        } else {
            Persisted::Stale
        })
    }

    pub fn check(&mut self, trigger: Trigger) {
        if self.busy() {
            return;
        }
        let now = Instant::now();
        if self.refresh_blocked() {
            self.schedule.arm_check(now);
            return;
        }
        let manual = trigger == Trigger::Manual;
        let previous = match &self.state {
            State::UpdatesAvailable(pending) => Some(pending.clone()),
            _ => None,
        };
        let failing_already = self.last_error.is_some();
        self.set_state(State::Checking);
        if manual {
            self.notifier.info(
                "Checking for updates",
                "Updating flake inputs and evaluating the new configuration.",
            );
        }

        match self.do_check(previous.as_ref()) {
            Ok(CheckOutcome::UpToDate) => {
                let checked_at = chrono::Local::now().format("%H:%M").to_string();
                self.set_last_error(None);
                self.set_state(State::UpToDate { checked_at });
                if manual {
                    self.notifier
                        .info("Up to date", "All flake inputs are current.");
                }
            }
            Ok(CheckOutcome::Unchanged) => {
                self.set_last_error(None);
                match previous {
                    Some(pending) => {
                        if manual {
                            self.notifier.info(
                                "No new changes",
                                &format!(
                                    "The pending update is still current: {}",
                                    pending.status_line()
                                ),
                            );
                        }
                        self.set_state(State::UpdatesAvailable(pending));
                    }
                    None => self.set_state(State::Idle),
                }
            }
            Ok(CheckOutcome::Updates(pending)) => {
                if let Err(err) = state::save_pending(&self.cfg.state_file(), &pending) {
                    log::warn!("failed to persist state: {err:#}");
                }
                self.set_last_error(None);
                // New by construction -- `Unchanged` caught the same update --
                // so a scheduled check notifies too.
                self.notifier.updates_available(&pending);
                self.set_state(State::UpdatesAvailable(pending));
                if !manual && self.cfg.auto_build {
                    self.build(Trigger::Scheduled);
                }
            }
            Err(err) => {
                let message = format!("{err:#}");
                log::error!("check failed: {message}");
                self.set_last_error(Some(ErrorReport::new(Operation::Check, message.clone())));
                // A scheduled check that keeps failing the same way goes to
                // the journal, not to the desktop every interval.
                if manual || !failing_already {
                    self.notifier
                        .failure("Update check failed".to_string(), tail(&message, 3));
                }
                self.set_state(State::Error {
                    message: truncate(&message, 4000),
                });
            }
        }
        self.schedule.arm_check(Instant::now());
    }

    /// Evaluation only: nothing is downloaded or built. Cheap enough to run
    /// on a schedule, and it yields the numbers -- installed packages that
    /// change, paths to fetch, derivations to build -- the decision to build
    /// is made on.
    fn do_check(&self, previous: Option<&PendingUpdate>) -> Result<CheckOutcome> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        let main_rev = git::rev_parse(flake, "main")?;
        git::ensure_worktree(flake, &worktree, &self.cfg.branch)?;

        // The old side first, while the worktree still sits at main.
        let old_system = nix::eval_roots(&self.cfg.system_roots_installable())?;
        let old_home = nix::eval_roots(&self.cfg.home_roots_installable())?;

        let update_log = nix::flake_update(&worktree)?;
        if !git::lock_changed(&worktree)? {
            return Ok(CheckOutcome::UpToDate);
        }

        // The same main with the same lock is the same update. Leaving it
        // alone is what keeps a re-check from throwing away a finished build,
        // and what lets a scheduled check stay silent.
        let lock_hash = git::hash_object(&worktree, "flake.lock")?;
        if let Some(previous) = previous {
            if previous.main_rev == main_rev && previous.lock_hash == lock_hash {
                return Ok(CheckOutcome::Unchanged);
            }
        }

        // Parsed only past the up-to-date return, so the no-op path stays free.
        // `ensure_worktree` hard-resets onto main every check, so this log is
        // always the complete main→new diff even on a re-check.
        let inputs = inputs::parse(&update_log);

        let new_system = nix::eval_roots(&self.cfg.system_roots_installable())?;
        let new_home = nix::eval_roots(&self.cfg.home_roots_installable())?;
        let system_roots = roots::diff(&old_system, &new_system, Scope::System);
        let home_roots = roots::diff(&old_home, &new_home, Scope::Home);
        let mut all_roots = system_roots.clone();
        all_roots.extend(home_roots.clone());
        let summary = Summary {
            total: roots::total(&all_roots),
            system: roots::counts(&system_roots),
            home: roots::counts(&home_roots),
        };

        // Fatal rather than decorative: the dry run evaluates both toplevels,
        // so a configuration that will not build fails here, at check time.
        let plan = nix::dry_run(&[
            &self.cfg.system_installable(),
            &self.cfg.home_installable(),
        ])?;

        // A new update supersedes whatever was built before; those out-links
        // would otherwise keep a closure nobody will apply alive.
        for link in [self.cfg.result_system(), self.cfg.result_home()] {
            match std::fs::remove_file(&link) {
                Ok(()) => log::info!("removed superseded out-link {}", link.display()),
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
                Err(err) => log::warn!("could not remove {}: {err}", link.display()),
            }
        }

        Ok(CheckOutcome::Updates(PendingUpdate {
            summary,
            system_path: None,
            home_path: None,
            main_rev,
            lock_hash,
            packages: Vec::new(),
            inputs,
            roots: all_roots,
            plan: Some(plan),
        }))
    }

    /// Build the pending update: download and build both closures, with
    /// progress, then diff them against what is running.
    pub fn build(&mut self, trigger: Trigger) {
        if self.busy() || self.refresh_blocked() {
            return;
        }
        let pending = match &self.state {
            State::UpdatesAvailable(pending) if !pending.built() => pending.clone(),
            State::UpdatesAvailable(_) => {
                log::info!("build requested but the update is already built");
                return;
            }
            _ => {
                log::info!("build requested but no update is pending");
                return;
            }
        };
        self.canceller.reset();
        let plan = pending.plan.unwrap_or_default();
        self.set_state(State::Building(Progress {
            plan,
            ..Progress::default()
        }));

        // An unattended build shows no progress notification; the tray
        // carries the bar, and the result notifies as usual.
        match self.do_build(&pending, trigger == Trigger::Scheduled) {
            Ok(BuildOutcome::Built(built)) => {
                if let Err(err) = state::save_pending(&self.cfg.state_file(), &built) {
                    log::warn!("failed to persist state: {err:#}");
                }
                self.set_last_error(None);
                self.notifier.updates_available(&built);
                self.set_state(State::UpdatesAvailable(built));
            }
            Ok(BuildOutcome::Cancelled(CancelReason::User)) => {
                self.notifier.info(
                    "Build cancelled",
                    "The update is still pending; build it again when convenient.",
                );
                self.set_state(State::UpdatesAvailable(pending));
            }
            Ok(BuildOutcome::Cancelled(CancelReason::Quit)) => {
                self.set_state(State::UpdatesAvailable(pending));
            }
            Ok(BuildOutcome::Stale { message }) => {
                state::clear_pending(&self.cfg.state_file());
                self.notifier.error("Update no longer applies", &message);
                self.set_state(State::Idle);
            }
            Err(err) => {
                // The update stays pending and unbuilt; the failure block hides
                // Build until the next successful check, as with a failed apply.
                let message = format!("{err:#}");
                log::error!("build failed: {message}");
                self.set_last_error(Some(ErrorReport::new(Operation::Build, message.clone())));
                self.notifier
                    .failure("Build failed".to_string(), tail(&message, 3));
                self.set_state(State::UpdatesAvailable(pending));
            }
        }
    }

    fn do_build(&self, p: &PendingUpdate, quiet: bool) -> Result<BuildOutcome> {
        let flake = &self.cfg.flake;
        let worktree = self.cfg.worktree();

        if git::rev_parse(flake, "main")? != p.main_rev {
            return Ok(BuildOutcome::Stale {
                message: "main moved since the last check; run Check for updates again."
                    .to_string(),
            });
        }
        if !worktree.join("flake.lock").is_file()
            || git::hash_object(&worktree, "flake.lock")? != p.lock_hash
        {
            return Ok(BuildOutcome::Stale {
                message: "The checked lock file is gone from the worktree; run Check for updates again."
                    .to_string(),
            });
        }

        let system = self.cfg.system_installable();
        let home = self.cfg.home_installable();
        // Fresh denominators: the store may have gained or lost paths since
        // the check, and the fraction should end at exactly 100 %.
        let plan: BuildPlan = nix::dry_run(&[&system, &home])?;

        let mut tracker = progress::Tracker::new();
        let mut reporter =
            Reporter::new(&self.tray, &self.notifier, &tracker.snapshot(&plan), quiet);

        let system_path = match nix::build_streaming(
            &system,
            &self.cfg.result_system(),
            &self.canceller,
            &mut tracker,
            |t| reporter.report(&t.snapshot(&plan), false),
        ) {
            Ok(nix::BuildOutcome::Built(path)) => path,
            Ok(nix::BuildOutcome::Cancelled(reason)) => {
                reporter.finish();
                return Ok(BuildOutcome::Cancelled(reason));
            }
            Err(err) => {
                reporter.finish();
                return Err(err);
            }
        };
        tracker.finish_build();
        reporter.report(&tracker.snapshot(&plan), true);

        let home_path = match nix::build_streaming(
            &home,
            &self.cfg.result_home(),
            &self.canceller,
            &mut tracker,
            |t| reporter.report(&t.snapshot(&plan), false),
        ) {
            Ok(nix::BuildOutcome::Built(path)) => path,
            Ok(nix::BuildOutcome::Cancelled(reason)) => {
                reporter.finish();
                return Ok(BuildOutcome::Cancelled(reason));
            }
            Err(err) => {
                reporter.finish();
                return Err(err);
            }
        };
        tracker.finish_build();
        reporter.report(&tracker.snapshot(&plan), true);
        reporter.finish();

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

        // Flattened here rather than merged: the dialog groups by scope, so a
        // package touched by both closures is legitimately two rows.
        let packages = flatten(&system_diff, Scope::System)
            .chain(flatten(&home_diff, Scope::Home))
            .collect();

        Ok(BuildOutcome::Built(PendingUpdate {
            summary,
            system_path: Some(system_path.display().to_string()),
            home_path: Some(home_path.display().to_string()),
            main_rev: p.main_rev.clone(),
            lock_hash: p.lock_hash.clone(),
            packages,
            inputs: p.inputs.clone(),
            roots: p.roots.clone(),
            plan: Some(plan),
        }))
    }

    pub fn apply(&mut self, mode: ApplyMode) {
        if self.busy() || self.refresh_blocked() {
            return;
        }
        let pending = match &self.state {
            State::UpdatesAvailable(p) if p.built() => p.clone(),
            State::UpdatesAvailable(_) => {
                log::info!("apply requested but the update has not been built");
                return;
            }
            _ => {
                log::info!("apply requested but no update is pending");
                return;
            }
        };
        self.set_state(State::Applying);
        self.notifier.info("Applying updates", mode.describe());

        match self.do_apply(&pending, mode) {
            Ok(ApplyOutcome::Applied {
                os_done,
                home_done,
                caveats,
            }) => {
                if os_done && home_done {
                    state::clear_pending(&self.cfg.state_file());
                    self.set_last_error(None);
                    let body = if mode == ApplyMode::HomeAndBoot {
                        format!(
                            "{}. The system generation takes effect on the next boot.",
                            pending.summary.short()
                        )
                    } else {
                        pending.summary.short()
                    };
                    if caveats.is_empty() {
                        self.notifier.info("Update applied", &body);
                    } else {
                        self.notifier
                            .error("Update applied with a caveat", &caveats.join("\n\n"));
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
                    if caveats.is_empty() {
                        self.notifier.info("Update partially applied", body);
                    } else {
                        let body = format!("{body}\n\n{}", caveats.join("\n\n"));
                        self.notifier.error("Update partially applied", &body);
                    }
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
                self.set_last_error(Some(ErrorReport::new(
                    Operation::Apply(mode),
                    message.clone(),
                )));
                self.notifier
                    .failure("Apply failed".to_string(), tail(&message, 3));
                self.set_state(State::UpdatesAvailable(pending));
            }
        }
    }

    /// Write a report about the last failure and open it. Both entry points --
    /// the tray menu and the error notification's buttons -- land here, so the
    /// report has exactly one writer.
    pub fn troubleshoot(&mut self, action: Action) {
        let Some(report) = &self.last_error else {
            log::info!("troubleshoot requested but no failure is recorded");
            return;
        };

        let result = troubleshoot::write(&self.cfg, report)
            .and_then(|path| troubleshoot::launch(&self.cfg, action, &path));
        if let Err(err) = result {
            log::error!("troubleshoot failed: {err:#}");
            // Plain error(): offering to troubleshoot the troubleshooter is
            // not a useful thing to do here.
            self.notifier
                .error("Could not open the failure report", &format!("{err:#}"));
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

        let (Some(system_str), Some(home_str)) = (&p.system_path, &p.home_path) else {
            return Ok(ApplyOutcome::Stale {
                message: "The update has not been built; build it first.".to_string(),
            });
        };
        let system_path = PathBuf::from(system_str);
        let home_path = PathBuf::from(home_str);
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
        let mut caveats = Vec::new();

        // The OS part first: run0 escalates through polkit, so the
        // authentication dialog comes from the session's agent and no setuid
        // binary is involved. `switch` activates now; `boot` only sets the
        // profile and boot entry. Both are skipped when already done.
        let helper_action = match mode.system_action() {
            SystemAction::Switch
                if std::fs::canonicalize("/run/current-system")
                    .context("resolving /run/current-system")?
                    != system_path =>
            {
                Some("switch")
            }
            SystemAction::Boot if !os_done => Some("boot"),
            SystemAction::None => None,
            _ => {
                log::info!("system part already applied, skipping");
                None
            }
        };
        if let Some(action) = helper_action {
            match self.run_system_helper(action, system_str)? {
                HelperOutcome::Done { warning } => {
                    os_done = true;
                    caveats.extend(warning);
                }
                HelperOutcome::Declined => return Ok(ApplyOutcome::Cancelled),
            }
        }

        // Merge the lock bump back into main as soon as both parts are done
        // or about to be — and *before* home activation, because the new home
        // generation contains a new daemon binary, so activating it can
        // restart this very service, and the merge must not be lost.
        if os_done && (home_done || mode.includes_home()) {
            if let Err(err) = self.merge_back(&p.main_rev) {
                caveats.push(format!(
                    "The update was applied, but flake.lock could not be fast-forwarded into \
                     main ({err:#}). Merge branch '{}' manually.",
                    self.cfg.branch
                ));
            }
        }

        // The home part, unprivileged, skipped if the profile already points
        // at the new generation.
        if mode.includes_home() && !home_done {
            log::info!("activating home generation: {home_str}");
            self.run_home_activation(&home_path)?;
            home_done = true;
        }

        Ok(ApplyOutcome::Applied {
            os_done,
            home_done,
            caveats,
        })
    }

    /// Run the new home generation's `activate` script.
    ///
    /// It runs as a transient user unit, not as a child of this process. The
    /// generation being activated usually carries a changed
    /// `stewos-update-manager.service` (a new daemon binary at the least),
    /// and sd-switch stops every changed unit before it starts any. Stopping
    /// this unit kills its whole cgroup, and with the script in it the
    /// activation died between those two phases: caelestia, the polkit agent
    /// and the daemon itself were stopped and nothing started them again.
    ///
    /// In its own unit the script outlives the daemon. This process may still
    /// be stopped before it returns, in which case the outcome is lost here
    /// and reported by `restore()` when the new daemon comes up.
    ///
    /// `systemd-run` is resolved from PATH, not the wrapper, for the same
    /// reason `run0` is: it has to match the running systemd. The unit gets
    /// the user manager's environment, which on NixOS carries the profile
    /// PATH the script needs for `nix-env`, `nix` and `systemctl`.
    fn run_home_activation(&self, home_path: &Path) -> Result<()> {
        let output = Command::new("systemd-run")
            .args([
                "--user",
                "--wait",
                "--pipe",
                "--collect",
                "--quiet",
                "--unit=stewos-update-manager-activate",
                "--description=StewOS update-manager home activation",
            ])
            .arg(home_path.join("activate"))
            .output()
            .context("failed to run home activation")?;
        if !output.status.success() {
            bail!(
                "home activation failed (retry an apply that includes home; completed \
                 parts are skipped):\n{}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
        }
        Ok(())
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

    /// Run the privileged helper via run0.
    ///
    /// The helper `exec`s `switch-to-configuration`, so its exit status is
    /// that program's. Status 4 is not a failed switch: the profile, the
    /// boot entry and the activation are all done, and it only means some
    /// unit was in the `failed` state afterwards -- any unit on the system,
    /// whether or not the switch touched it. Treating that as a failure
    /// would leave the lock unmerged and home stale while the new system is
    /// already running, which is exactly what the retry guards would then
    /// skip. So it counts as done, with the warning carried as a caveat.
    fn run_system_helper(&self, action: &str, system_path: &str) -> Result<HelperOutcome> {
        let helper = apply_helper()?;
        log::info!("running system {action} via run0: {system_path}");
        let output = Command::new("run0")
            .arg("--pipe")
            .arg(helper)
            .arg(action)
            .arg(system_path)
            .output()
            .context("failed to run run0")?;
        if output.status.success() {
            return Ok(HelperOutcome::Done { warning: None });
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        if output.status.code() == Some(SWITCH_UNITS_FAILED) {
            let warning = units_failed_warning(&stderr);
            log::warn!("system {action} finished with failed units: {warning}");
            return Ok(HelperOutcome::Done {
                warning: Some(warning),
            });
        }
        if auth_declined(&stderr) {
            log::warn!("run0 authentication declined: {}", stderr.trim());
            return Ok(HelperOutcome::Declined);
        }
        bail!("system {action} failed:\n{}", stderr.trim());
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

/// What the privileged helper came back with.
enum HelperOutcome {
    /// The profile and boot entry are set and, for `switch`, the activation
    /// ran. `warning` is set when it exited with [`SWITCH_UNITS_FAILED`].
    Done { warning: Option<String> },
    /// The authentication dialog was declined; nothing changed.
    Declined,
}

/// `switch-to-configuration`'s exit status when the activation completed but
/// some units are in the `failed` state afterwards.
const SWITCH_UNITS_FAILED: i32 = 4;

/// The user-facing caveat for a switch that exited [`SWITCH_UNITS_FAILED`].
/// Quotes switch-to-configuration's own list of failed units when it can be
/// found in `stderr`, and the last few lines otherwise.
fn units_failed_warning(stderr: &str) -> String {
    const PREFIX: &str = "warning: the following units failed: ";
    let units = stderr
        .lines()
        .rev()
        .find_map(|line| line.trim().strip_prefix(PREFIX))
        .map(str::trim)
        .filter(|units| !units.is_empty());
    match units {
        Some(units) => format!(
            "The system was activated, but these units failed during the switch: {units}. \
             Check them with `systemctl --failed`."
        ),
        None => format!(
            "The system was activated, but some units failed during the switch. Check them \
             with `systemctl --failed`.\n{}",
            tail(stderr.trim(), 3)
        ),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_failed_units_warning_quotes_switch_to_configurations_list() {
        let stderr = "activating the configuration...\n\
                      starting the following units: polkit.service\n\
                      warning: the following units failed: fwupd-refresh.service\n\
                      \u{d7} fwupd-refresh.service - Refresh fwupd metadata and update motd\n";
        let warning = units_failed_warning(stderr);
        assert!(warning.starts_with("The system was activated, but these units failed"));
        assert!(warning.contains("fwupd-refresh.service."));
        assert!(!warning.contains("Refresh fwupd metadata"));
    }

    #[test]
    fn the_failed_units_warning_falls_back_to_the_tail() {
        let warning = units_failed_warning("one\ntwo\nthree\nfour\n");
        assert!(warning.starts_with("The system was activated, but some units failed"));
        assert!(warning.ends_with("two\nthree\nfour"));
    }

    #[test]
    fn no_interval_means_no_scheduled_check() {
        let now = Instant::now();
        let schedule = Schedule::new(None, now);
        assert!(!schedule.check_due(now + Duration::from_secs(86_400 * 365)));
        assert_eq!(schedule.wakeup(now), Schedule::IDLE);
    }

    #[test]
    fn a_check_comes_due_one_interval_after_it_was_armed() {
        let now = Instant::now();
        let interval = Duration::from_secs(600);
        let mut schedule = Schedule::new(Some(interval), now);
        assert!(!schedule.check_due(now + Duration::from_secs(599)));
        assert!(schedule.check_due(now + interval));
        assert_eq!(schedule.wakeup(now + Duration::from_secs(100)), Duration::from_secs(500));

        // Re-arming from later pushes it out: a manual check resets the clock.
        let later = now + Duration::from_secs(500);
        schedule.arm_check(later);
        assert!(!schedule.check_due(now + interval));
        assert!(schedule.check_due(later + interval));
    }

    #[test]
    fn the_blocked_poll_is_the_sooner_timer_and_clears() {
        let now = Instant::now();
        let mut schedule = Schedule::new(Some(Duration::from_secs(3600)), now);
        schedule.arm_blocked_poll(now);
        assert_eq!(schedule.wakeup(now), Schedule::BLOCKED_POLL);
        assert!(schedule.blocked_poll_due(now + Schedule::BLOCKED_POLL));
        schedule.clear_blocked_poll();
        assert!(!schedule.blocked_poll_due(now + Schedule::BLOCKED_POLL));
        assert_eq!(schedule.wakeup(now), Duration::from_secs(3600));
    }

    #[test]
    fn a_due_timer_wakes_immediately_and_the_idle_sleep_is_bounded() {
        let now = Instant::now();
        let schedule = Schedule::new(Some(Duration::from_secs(1)), now);
        assert_eq!(schedule.wakeup(now + Duration::from_secs(5)), Duration::ZERO);
        let idle = Schedule::new(Some(Duration::from_secs(86_400 * 30)), now);
        assert_eq!(idle.wakeup(now), Schedule::IDLE);
    }
}
