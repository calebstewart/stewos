use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

// Counts and Summary live in the shared library because the review dialog
// renders them too; they are re-exported here so the daemon's own modules can
// keep using `state::Summary`.
pub use stewos_update_manager::Summary;

use stewos_update_manager::{
    ApplyMode, InputChange, PackageChange, ReviewRequest, PROTOCOL_VERSION,
};

/// Everything needed to apply a checked update, persisted to state.json so the
/// "updates available" state survives a daemon or session restart.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingUpdate {
    pub summary: Summary,
    pub system_path: String,
    pub home_path: String,
    /// Commit `main` pointed at when the check ran; apply refuses if it moved.
    pub main_rev: String,
    /// Per-package detail for the review dialog.
    ///
    /// `#[serde(default)]` is load-bearing, not tidiness: `load_pending`
    /// swallows any deserialize error and returns None, so without a default a
    /// state.json written before these fields existed would be silently
    /// discarded on upgrade -- which the user sees as the tray forgetting a
    /// pending update.
    #[serde(default)]
    pub packages: Vec<PackageChange>,
    #[serde(default)]
    pub inputs: Vec<InputChange>,
}

impl PendingUpdate {
    /// The snapshot handed to the review dialog.
    ///
    /// It is only a snapshot: the daemon re-validates the rev and the
    /// out-links at apply time, so a request that goes stale while the window
    /// is open produces an apply the daemon refuses.
    pub fn review_request(&self, host: &str) -> ReviewRequest {
        ReviewRequest {
            version: PROTOCOL_VERSION,
            host: host.to_string(),
            summary: self.summary.clone(),
            packages: self.packages.clone(),
            inputs: self.inputs.clone(),
            modes: ApplyMode::MENU_ORDER.to_vec(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum State {
    Idle,
    Checking,
    UpToDate { checked_at: String },
    UpdatesAvailable(PendingUpdate),
    Applying,
    Error { message: String },
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

    /// The detail fields were added after the first release, so a state.json
    /// without them must still load. If this regresses, the first run after an
    /// upgrade silently drops the pending update.
    #[test]
    fn loads_a_state_file_written_before_the_detail_fields_existed() {
        let old = r#"{
            "summary": {
                "total": {"upgraded": 1, "added": 0, "removed": 0},
                "system": {"upgraded": 1, "added": 0, "removed": 0},
                "home": {"upgraded": 0, "added": 0, "removed": 0}
            },
            "system_path": "/nix/store/aaa-nixos-system-host",
            "home_path": "/nix/store/bbb-home-manager-generation",
            "main_rev": "deadbeef"
        }"#;
        let pending: PendingUpdate = serde_json::from_str(old).unwrap();
        assert_eq!(pending.main_rev, "deadbeef");
        assert!(pending.packages.is_empty());
        assert!(pending.inputs.is_empty());
    }

    #[test]
    fn review_request_offers_every_mode() {
        let pending = PendingUpdate {
            summary: Summary {
                total: Counts::default(),
                system: Counts::default(),
                home: Counts::default(),
            },
            system_path: "/nix/store/aaa".into(),
            home_path: "/nix/store/bbb".into(),
            main_rev: "abc".into(),
            packages: Vec::new(),
            inputs: Vec::new(),
        };
        let req = pending.review_request("framework-desktop");
        assert_eq!(req.version, PROTOCOL_VERSION);
        assert_eq!(req.host, "framework-desktop");
        assert_eq!(req.modes.len(), 4);
        assert_eq!(req.modes[0], ApplyMode::Full);
    }
}
