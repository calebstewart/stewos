mod config;
mod icons;
mod notify;
mod review;
mod state;
mod tray;
mod troubleshoot;
mod updater;

use std::sync::mpsc;
use std::sync::Arc;

use anyhow::Result;
use clap::Parser;

/// Defined in the shared library because the review dialog renders these too.
pub use stewos_update_manager::ApplyMode;

/// Requests handled by the worker loop. The tray menu, the notification action
/// threads and the review dialog's reader thread only ever send these; all real
/// work happens on the main thread, so a check and an apply can never overlap.
///
/// Every variant is `Copy`, and must stay that way: `tray.rs`'s menu closures
/// are `Box<dyn Fn(&mut T)>`, not `FnOnce`, so a payload that cannot be copied
/// out of the closure will not compile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Check,
    Apply(ApplyMode),
    /// Open the review window on the pending update.
    ReviewChanges,
    /// Write a report about the last failure and open it.
    Troubleshoot(troubleshoot::Action),
    Quit,
}

fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let cfg = config::Args::parse().resolve()?;
    log::info!(
        "flake={} host={} user={} branch={} cache={}",
        cfg.flake.display(),
        cfg.host,
        cfg.user,
        cfg.branch,
        cfg.cache_dir.display()
    );
    std::fs::create_dir_all(&cfg.cache_dir)?;

    let (tx, rx) = mpsc::channel::<Command>();

    let icons = Arc::new(icons::Icons::load(cfg.icon_dir.as_deref()));

    // With no terminal to open them in, the troubleshooting entries would be
    // dead weight, so the tray leaves them out entirely.
    let troubleshoot_available = cfg.terminal.is_some();
    if !troubleshoot_available {
        log::warn!("no terminal configured; troubleshooting entries are disabled");
    }

    // Same reasoning as the troubleshooting entries: with no dialog to open,
    // a Review entry would be dead weight, so the tray leaves it out.
    let review_dialog = cfg.review_dialog.clone();
    if review_dialog.is_none() {
        log::warn!("no review dialog found; the review entry is disabled");
    }

    let tray_service = ksni::TrayService::new(tray::UpdateTray::new(
        tx.clone(),
        icons.clone(),
        troubleshoot_available,
        review_dialog.is_some(),
    ));
    let tray = tray_service.handle();
    tray_service.spawn();

    let notifier = notify::Notifier::new(tx.clone(), icons);
    let reviewer = review_dialog.map(|dialog| review::Reviewer::new(tx, dialog));
    let mut worker = updater::Worker::new(cfg, notifier, tray.clone(), reviewer);
    worker.restore();

    loop {
        match rx.recv() {
            Ok(Command::Check) => worker.check(),
            Ok(Command::Apply(mode)) => worker.apply(mode),
            Ok(Command::ReviewChanges) => worker.review(),
            Ok(Command::Troubleshoot(action)) => worker.troubleshoot(action),
            Ok(Command::Quit) | Err(_) => break,
        }
    }

    tray.shutdown();
    Ok(())
}
