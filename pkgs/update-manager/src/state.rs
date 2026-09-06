use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

// Counts and Summary live in the shared library because the review dialog
// renders them too; they are re-exported here so the daemon's own modules can
// keep using `state::Summary`.
pub use stewos_update_manager::Summary;

use stewos_update_manager::{
    human_bytes, ApplyMode, BuildPlan, InputChange, PackageChange, ReviewRequest,
    PROTOCOL_VERSION,
};

/// Everything known about a checked update, persisted to state.json so the
/// "updates available" state survives a daemon or session restart.
///
/// It exists in two shapes. Fresh from a check it is *unbuilt*: the lock has
/// moved in the worktree, `roots`, `inputs` and `plan` say what that means,
/// and the out-link paths are `None`. Once built, both paths are `Some` and
/// `packages`/`summary` carry the closure diff. [`PendingUpdate::built`] is
/// derived from the paths rather than stored, so it cannot disagree with them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingUpdate {
    pub summary: Summary,
    pub system_path: Option<String>,
    pub home_path: Option<String>,
    /// Commit `main` pointed at when the check ran; build and apply refuse if
    /// it moved.
    pub main_rev: String,
    /// `git hash-object` of the updated `flake.lock` in the worktree. It is
    /// what identifies an unbuilt update: the same `main_rev` with the same
    /// lock is the same update, and a re-check must not disturb it.
    ///
    /// `#[serde(default)]` is load-bearing on every field added since the
    /// first release, not tidiness: `load_pending` swallows any deserialize
    /// error and returns None, so without a default a state.json written
    /// before the field existed would be silently discarded on upgrade --
    /// which the user sees as the tray forgetting a pending update.
    #[serde(default)]
    pub lock_hash: String,
    /// Per-package closure detail for the review dialog; empty until built.
    #[serde(default)]
    pub packages: Vec<PackageChange>,
    #[serde(default)]
    pub inputs: Vec<InputChange>,
    /// Changes to the directly installed packages, known from evaluation.
    #[serde(default)]
    pub roots: Vec<PackageChange>,
    /// What the build will fetch and build, from the dry run at check time.
    #[serde(default)]
    pub plan: Option<BuildPlan>,
}

impl PendingUpdate {
    pub fn built(&self) -> bool {
        self.system_path.is_some() && self.home_path.is_some()
    }

    /// The snapshot handed to the review dialog.
    ///
    /// It is only a snapshot: the daemon re-validates the rev and the
    /// out-links at build and apply time, so a request that goes stale while
    /// the window is open produces a request the daemon refuses.
    pub fn review_request(&self, host: &str) -> ReviewRequest {
        ReviewRequest {
            version: PROTOCOL_VERSION,
            host: host.to_string(),
            summary: self.summary.clone(),
            packages: self.packages.clone(),
            inputs: self.inputs.clone(),
            modes: ApplyMode::MENU_ORDER.to_vec(),
            built: self.built(),
            plan: self.plan,
            roots: self.roots.clone(),
        }
    }

    /// The menu's one-line status.
    pub fn status_line(&self) -> String {
        if self.built() {
            self.summary.short()
        } else {
            format!("{} \u{00b7} not built", self.summary.short())
        }
    }
}

/// Where a build is, as a small snapshot the tray and the notification can
/// render. The counters and the plan are the same units -- paths fetched and
/// derivations built -- so the fraction is exact and monotonic; bytes are
/// shown but never used to compute it.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Progress {
    pub plan: BuildPlan,
    pub paths_done: u64,
    pub drvs_done: u64,
    pub bytes_done: u64,
    /// The derivation currently being built locally, if any, and its phase.
    pub current: Option<String>,
    pub phase: Option<String>,
    pub failed: u64,
}

impl Progress {
    pub fn fraction(&self) -> f32 {
        let units = self.plan.units();
        if units == 0 {
            return 1.0;
        }
        ((self.paths_done + self.drvs_done) as f32 / units as f32).clamp(0.0, 1.0)
    }

    pub fn percent(&self) -> u8 {
        (self.fraction() * 100.0).round() as u8
    }

    /// "Building 43% · 120/386 paths · 3/7 built"
    pub fn line(&self) -> String {
        let mut parts = vec![format!("Building {}%", self.percent())];
        if self.plan.paths > 0 {
            let done = self.paths_done.min(u64::from(self.plan.paths));
            parts.push(format!("{done}/{} paths", self.plan.paths));
        }
        if self.plan.derivations > 0 {
            let done = self.drvs_done.min(u64::from(self.plan.derivations));
            parts.push(format!("{done}/{} built", self.plan.derivations));
        }
        parts.join(" \u{00b7} ")
    }

    /// The line plus what it is doing right now, for the tooltip and the
    /// notification body.
    pub fn detail(&self) -> String {
        let mut lines = vec![self.line()];
        if self.plan.download_bytes > 0 {
            let done = self.bytes_done.min(self.plan.download_bytes);
            lines.push(format!(
                "{} of {} downloaded",
                human_bytes(done),
                human_bytes(self.plan.download_bytes)
            ));
        }
        if let Some(current) = &self.current {
            lines.push(match &self.phase {
                Some(phase) => format!("{current} ({phase})"),
                None => current.clone(),
            });
        }
        lines.join("\n")
    }
}

#[derive(Debug, Clone)]
pub enum State {
    Idle,
    Checking,
    UpToDate { checked_at: String },
    UpdatesAvailable(PendingUpdate),
    Building(Progress),
    Applying,
    Error { message: String },
    /// Uncommitted changes in the flake checkout. Not an error: nothing failed,
    /// and it clears itself once they are committed or discarded.
    Blocked { reason: String },
}

pub fn save_pending(path: &Path, pending: &PendingUpdate) -> Result<()> {
    let json = serde_json::to_string_pretty(pending)?;
    std::fs::write(path, json).with_context(|| format!("writing {}", path.display()))
}

pub fn load_pending(path: &Path) -> Option<PendingUpdate> {
    let data = std::fs::read_to_string(path).ok()?;
    match serde_json::from_str(&data) {
        Ok(p) => Some(p),
        Err(err) => {
            log::warn!("ignoring unreadable {}: {err}", path.display());
            None
        }
    }
}

pub fn clear_pending(path: &Path) {
    if path.exists() {
        if let Err(err) = std::fs::remove_file(path) {
            log::warn!("failed to remove {}: {err}", path.display());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stewos_update_manager::Counts;

    const SUMMARY: &str = r#""summary": {
        "total": {"upgraded": 1, "added": 0, "removed": 0},
        "system": {"upgraded": 1, "added": 0, "removed": 0},
        "home": {"upgraded": 0, "added": 0, "removed": 0}
    }"#;

    /// The detail fields were added after the first release, so a state.json
    /// without them must still load. If this regresses, the first run after an
    /// upgrade silently drops the pending update.
    #[test]
    fn loads_a_state_file_written_before_the_detail_fields_existed() {
        let old = format!(
            r#"{{ {SUMMARY},
            "system_path": "/nix/store/aaa-nixos-system-host",
            "home_path": "/nix/store/bbb-home-manager-generation",
            "main_rev": "deadbeef"
        }}"#
        );
        let pending: PendingUpdate = serde_json::from_str(&old).unwrap();
        assert_eq!(pending.main_rev, "deadbeef");
        assert!(pending.packages.is_empty());
        assert!(pending.inputs.is_empty());
        // Paths written as plain strings by a v1 daemon load as built.
        assert!(pending.built());
        assert_eq!(pending.lock_hash, "");
        assert!(pending.plan.is_none());
    }

    #[test]
    fn an_unbuilt_update_has_no_paths() {
        let json = format!(
            r#"{{ {SUMMARY},
            "system_path": null, "home_path": null,
            "main_rev": "deadbeef", "lock_hash": "cafe",
            "plan": {{"paths": 3, "derivations": 0, "download_bytes": 10, "unpacked_bytes": 20}}
        }}"#
        );
        let pending: PendingUpdate = serde_json::from_str(&json).unwrap();
        assert!(!pending.built());
        assert_eq!(pending.plan.unwrap().paths, 3);
        assert!(pending.status_line().ends_with("not built"));
        assert!(!pending.review_request("h").built);
    }

    #[test]
    fn review_request_offers_every_mode() {
        let pending = PendingUpdate {
            summary: Summary {
                total: Counts::default(),
                system: Counts::default(),
                home: Counts::default(),
            },
            system_path: Some("/nix/store/aaa".into()),
            home_path: Some("/nix/store/bbb".into()),
            main_rev: "deadbeef".into(),
            lock_hash: String::new(),
            packages: Vec::new(),
            inputs: Vec::new(),
            roots: Vec::new(),
            plan: None,
        };
        let request = pending.review_request("host");
        assert_eq!(request.version, PROTOCOL_VERSION);
        assert_eq!(request.modes, ApplyMode::MENU_ORDER.to_vec());
        assert!(request.built);
    }

    fn progress(paths_done: u64, drvs_done: u64) -> Progress {
        Progress {
            plan: BuildPlan {
                paths: 386,
                derivations: 7,
                download_bytes: 466_616_320,
                unpacked_bytes: 0,
            },
            paths_done,
            drvs_done,
            bytes_done: 53_687_091,
            current: Some("firefox".into()),
            phase: Some("buildPhase".into()),
            failed: 0,
        }
    }

    #[test]
    fn progress_renders_counts_bytes_and_the_current_build() {
        let p = progress(120, 3);
        assert_eq!(p.percent(), 31);
        assert_eq!(
            p.line(),
            "Building 31% \u{00b7} 120/386 paths \u{00b7} 3/7 built"
        );
        assert_eq!(
            p.detail(),
            "Building 31% \u{00b7} 120/386 paths \u{00b7} 3/7 built\n51.2 MiB of 445.0 MiB downloaded\nfirefox (buildPhase)"
        );
        // Overshoot (nix counted something the plan did not) is clamped.
        assert_eq!(progress(400, 9).percent(), 100);
        assert!(progress(400, 9).line().contains("386/386 paths"));
    }

    #[test]
    fn progress_omits_what_the_plan_has_none_of() {
        let mut p = progress(0, 0);
        p.plan.derivations = 0;
        p.plan.download_bytes = 0;
        p.current = None;
        assert_eq!(p.line(), "Building 0% \u{00b7} 0/386 paths");
        assert_eq!(p.detail(), p.line());
    }
}
