mod config;
mod notify;
mod state;
mod tray;
mod updater;

use std::sync::mpsc;

use anyhow::Result;
use clap::Parser;

/// What an apply should cover. Only the variants that touch the OS need
/// privileged execution (via run0); a home-only apply runs entirely as the
/// user.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApplyMode {
    /// Switch the OS now and activate home.
    Full,
    /// Activate home only; the OS part stays pending.
    HomeOnly,
    /// Activate home and stage the OS generation for the next boot.
    HomeAndBoot,
    /// Switch the OS now only; the home part stays pending.
    SystemOnly,
}

/// Requests handled by the worker loop. The tray menu and notification action
/// threads only ever send these; all real work happens on the main thread, so
/// a check and an apply can never overlap.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Check,
    Apply(ApplyMode),
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

    let tray_service = ksni::TrayService::new(tray::UpdateTray::new(tx.clone()));
    let tray = tray_service.handle();
    tray_service.spawn();

    let notifier = notify::Notifier::new(tx);
    let mut worker = updater::Worker::new(cfg, notifier, tray.clone());
    worker.restore();

    loop {
        match rx.recv() {
            Ok(Command::Check) => worker.check(),
            Ok(Command::Apply(mode)) => worker.apply(mode),
            Ok(Command::Quit) | Err(_) => break,
        }
    }

    tray.shutdown();
    Ok(())
}
