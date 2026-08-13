//! The daemon's own status art.
//!
//! The icons are rendered to PNG by a separate derivation
//! (`pkgs/update-manager-icons`) and handed to us as an icon-theme root, so
//! recolouring them never rebuilds this crate. We serve them to the tray as
//! pixmaps rather than by name: an SNI host resolves names against whatever
//! icon theme it happens to have, which is exactly the dependency this is
//! meant to remove.
//!
//! Everything degrades to the old freedesktop names if the directory is
//! missing, which is what keeps a plain `cargo run` working.

use std::fs::File;
use std::path::{Path, PathBuf};

/// Sizes offered to the tray. The host picks; anything larger is wasted bytes
/// on every property fetch, since `ksni` re-hashes the whole set on each
/// update.
const TRAY_SIZES: [u32; 5] = [16, 22, 24, 32, 48];

/// Notification servers draw much larger than a tray does.
const NOTIFY_SIZE: u32 = 64;

/// Menu icons go out as raw PNG rather than pixmaps (that is what dbusmenu's
/// `icon-data` takes), so there is one size and the host scales it.
const MENU_SIZE: u32 = 24;

/// One icon per [`crate::state::State`] variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Icon {
    Idle,
    Checking,
    UpToDate,
    UpdatesAvailable,
    Applying,
    Error,
}

impl Icon {
    const ALL: [Icon; 6] = [
        Icon::Idle,
        Icon::Checking,
        Icon::UpToDate,
        Icon::UpdatesAvailable,
        Icon::Applying,
        Icon::Error,
    ];

    /// File stem, matching the SVG sources in `pkgs/update-manager-icons`.
    fn slug(self) -> &'static str {
        match self {
            Icon::Idle => "idle",
            Icon::Checking => "checking",
            Icon::UpToDate => "up-to-date",
            Icon::UpdatesAvailable => "updates-available",
            Icon::Applying => "applying",
            Icon::Error => "error",
        }
    }

    /// What we ask the ambient icon theme for when our own art is unavailable.
    fn fallback_name(self) -> &'static str {
        match self {
            Icon::Idle | Icon::UpToDate => "system-software-update",
            Icon::Checking | Icon::Applying => "emblem-synchronizing",
            Icon::UpdatesAvailable => "software-update-available",
            Icon::Error => "software-update-urgent",
        }
    }

    fn index(self) -> usize {
        Icon::ALL.iter().position(|i| *i == self).unwrap()
    }
}

/// One glyph per tray-menu entry. These are Actions rather than Status icons,
/// which is what lets [`Icon::Checking`] and [`MenuIcon::Search`] both exist.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuIcon {
    Search,
    Apply,
    Report,
    Troubleshoot,
    Quit,
}

impl MenuIcon {
    // Positional: `index` is a lookup into the loaded set, so append rather
    // than reorder.
    const ALL: [MenuIcon; 5] = [
        MenuIcon::Search,
        MenuIcon::Apply,
        MenuIcon::Report,
        MenuIcon::Troubleshoot,
        MenuIcon::Quit,
    ];

    fn slug(self) -> &'static str {
        match self {
            MenuIcon::Search => "search",
            MenuIcon::Apply => "apply",
            MenuIcon::Report => "report",
            MenuIcon::Troubleshoot => "troubleshoot",
            MenuIcon::Quit => "quit",
        }
    }

    fn fallback_name(self) -> &'static str {
        match self {
            MenuIcon::Search => "view-refresh",
            MenuIcon::Apply => "dialog-ok-apply",
            MenuIcon::Report => "text-x-generic",
            MenuIcon::Troubleshoot => "system-search",
            MenuIcon::Quit => "application-exit",
        }
    }

    fn index(self) -> usize {
        MenuIcon::ALL.iter().position(|i| *i == self).unwrap()
    }
}

#[derive(Default)]
struct Set {
    pixmaps: Vec<ksni::Icon>,
    notify_path: Option<PathBuf>,
}

pub struct Icons {
    sets: Vec<Set>,
    /// Raw PNG bytes, indexed by [`MenuIcon::index`].
    menu: Vec<Vec<u8>>,
}

impl Icons {
    /// Load every size of every icon from an icon-theme root (the `share/icons`
    /// of the icons derivation). A missing or unreadable set is a warning, not
    /// an error: the caller falls back to theme names.
    pub fn load(root: Option<&Path>) -> Self {
        let sets = Icon::ALL.iter().map(|icon| load_set(root, *icon)).collect();
        let menu = MenuIcon::ALL
            .iter()
            .map(|icon| load_menu(root, *icon))
            .collect();
        Self { sets, menu }
    }

    fn set(&self, icon: Icon) -> &Set {
        &self.sets[icon.index()]
    }

    /// Pixmaps for the tray, in ARGB32 network byte order. Empty when the art
    /// could not be loaded, in which case [`Icons::name`] supplies a theme name
    /// instead.
    pub fn pixmaps(&self, icon: Icon) -> Vec<ksni::Icon> {
        self.set(icon).pixmaps.clone()
    }

    /// The tray's `IconName`. Empty whenever we have pixmaps to offer: a host
    /// prefers the name when it is set and resolvable, so leaving one here
    /// would mean our own art is never drawn.
    pub fn name(&self, icon: Icon) -> String {
        if self.set(icon).pixmaps.is_empty() {
            icon.fallback_name().to_string()
        } else {
            String::new()
        }
    }

    /// What to hand a notification server: an absolute path to our own PNG, or
    /// a theme name if we have none.
    pub fn notify_icon(&self, icon: Icon) -> String {
        match &self.set(icon).notify_path {
            Some(path) => path.display().to_string(),
            None => icon.fallback_name().to_string(),
        }
    }

    /// A menu entry's icon as raw PNG, which is what dbusmenu's `icon-data`
    /// wants. Empty when we have none, in which case [`Icons::menu_name`]
    /// supplies a theme name.
    pub fn menu_data(&self, icon: MenuIcon) -> Vec<u8> {
        self.menu[icon.index()].clone()
    }

    /// Empty whenever `icon-data` is available, for the same reason
    /// [`Icons::name`] is: a host that can resolve the name will prefer it.
    pub fn menu_name(&self, icon: MenuIcon) -> String {
        if self.menu[icon.index()].is_empty() {
            icon.fallback_name().to_string()
        } else {
            String::new()
        }
    }
}

fn load_set(root: Option<&Path>, icon: Icon) -> Set {
    let Some(root) = root else {
        return Set::default();
    };

    let mut pixmaps = Vec::with_capacity(TRAY_SIZES.len());
    for size in TRAY_SIZES {
        match load_pixmap(&icon_path(root, icon, size)) {
            Ok(pixmap) => pixmaps.push(pixmap),
            Err(err) => {
                log::warn!(
                    "falling back to theme icons: {} at {size}px: {err}",
                    icon.slug()
                );
                return Set::default();
            }
        }
    }

    let notify = icon_path(root, icon, NOTIFY_SIZE);
    Set {
        pixmaps,
        notify_path: notify.is_file().then_some(notify),
    }
}

fn load_menu(root: Option<&Path>, icon: MenuIcon) -> Vec<u8> {
    let Some(root) = root else {
        return Vec::new();
    };

    let path = png_path(root, "actions", icon.slug(), MENU_SIZE);
    std::fs::read(&path).unwrap_or_else(|err| {
        log::warn!(
            "falling back to a theme icon for the {} menu item: {err}",
            icon.slug()
        );
        Vec::new()
    })
}

fn icon_path(root: &Path, icon: Icon, size: u32) -> PathBuf {
    png_path(root, "status", icon.slug(), size)
}

fn png_path(root: &Path, context: &str, slug: &str, size: u32) -> PathBuf {
    root.join(format!("hicolor/{size}x{size}/{context}"))
        .join(format!("stewos-update-{slug}.png"))
}

/// Decode a PNG into the pixel format the StatusNotifierItem spec asks for:
/// ARGB32 in network (big-endian) byte order, i.e. bytes `[A, R, G, B]`.
///
/// PNG is never premultiplied, and neither is `QImage::Format_ARGB32` on the
/// host side, so this is a channel reorder and nothing more.
fn load_pixmap(path: &Path) -> anyhow::Result<ksni::Icon> {
    let decoder = png::Decoder::new(File::open(path)?);
    let mut reader = decoder.read_info()?;
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf)?;

    anyhow::ensure!(
        info.bit_depth == png::BitDepth::Eight,
        "expected an 8-bit PNG, got {:?}",
        info.bit_depth
    );
    let channels = match info.color_type {
        png::ColorType::Rgba => 4,
        png::ColorType::Rgb => 3,
        other => anyhow::bail!("expected an RGB(A) PNG, got {other:?}"),
    };

    let pixels = &buf[..info.buffer_size()];
    let mut data = Vec::with_capacity(info.width as usize * info.height as usize * 4);
    for px in pixels.chunks_exact(channels) {
        let alpha = if channels == 4 { px[3] } else { 0xff };
        data.extend_from_slice(&[alpha, px[0], px[1], px[2]]);
    }

    Ok(ksni::Icon {
        width: info.width as i32,
        height: info.height as i32,
        data,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The channel reorder is the one part of this that fails silently -- a
    /// swapped icon still renders, just in the wrong colour. Encode a known
    /// pixel and check the bytes land where the spec says they do.
    #[test]
    fn decodes_to_argb32_big_endian() {
        let dir = std::env::temp_dir().join("stewos-update-manager-icon-test");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("one-pixel.png");

        // Opaque #336699, non-premultiplied.
        let source = [0x33u8, 0x66, 0x99, 0xff];
        let file = File::create(&path).unwrap();
        let mut encoder = png::Encoder::new(file, 1, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder
            .write_header()
            .unwrap()
            .write_image_data(&source)
            .unwrap();

        let icon = load_pixmap(&path).unwrap();
        assert_eq!(icon.width, 1);
        assert_eq!(icon.height, 1);
        assert_eq!(icon.data, vec![0xff, 0x33, 0x66, 0x99]);

        std::fs::remove_file(&path).unwrap();
    }
}
