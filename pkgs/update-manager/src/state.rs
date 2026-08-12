use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Counts {
    pub upgraded: u32,
    pub added: u32,
    pub removed: u32,
}

impl Counts {
    pub fn is_zero(&self) -> bool {
        self.upgraded == 0 && self.added == 0 && self.removed == 0
    }

    fn arrows(&self) -> String {
        format!("{}\u{2191} {}+ {}\u{2212}", self.upgraded, self.added, self.removed)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Summary {
    /// Union of the system and home diffs, deduplicated by package name.
    pub total: Counts,
    pub system: Counts,
    pub home: Counts,
}

impl Summary {
    /// Short menu/notification line: "12 updated, 3 new, 1 removed".
    pub fn short(&self) -> String {
        if self.total.is_zero() {
            "Lock updated, no package changes".to_string()
        } else {
            format!(
                "{} updated, {} new, {} removed",
                self.total.upgraded, self.total.added, self.total.removed
            )
        }
    }

    /// Per-target breakdown for the tooltip.
    pub fn breakdown(&self) -> String {
        format!(
            "System: {} \u{00b7} Home: {}",
            self.system.arrows(),
            self.home.arrows()
        )
    }
}

/// Everything needed to apply a checked update, persisted to state.json so the
/// "updates available" state survives a daemon or session restart.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingUpdate {
    pub summary: Summary,
    pub system_path: String,
    pub home_path: String,
    /// Commit `main` pointed at when the check ran; apply refuses if it moved.
    pub main_rev: String,
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
