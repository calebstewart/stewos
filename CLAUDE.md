# StewOS

A Nix flake managing NixOS, Nix-Darwin (macOS) and Home-Manager configurations
for several machines, along with the modules, packages and helper libraries they
are built from. All configuration lives under options named `stewos.*`.

## Project Structure

```
stewos/
├── flake.nix          # Inputs + every output, declared explicitly.
│                      # The only place flake inputs are captured.
├── overlays/          # The StewOS overlay (adds pkgs.stewos.*)
├── pkgs/              # Package definitions; plain callPackage derivations
│   └── default.nix    # Explicit list of every package in the scope
├── lib/               # Pure helpers: takes a nixpkgs lib, returns functions
│   ├── desktop.nix    # Shared desktop helpers (command line construction)
│   ├── rofi.nix       # Rofi command line construction
│   └── rasi/          # RASI DSL for Rofi theme generation
├── modules/
│   ├── common/        # Options shared by NixOS and Home-Manager
│   ├── nixos/         # NixOS system modules (default.nix lists them)
│   ├── home-manager/  # Home-Manager user modules
│   └── nix-darwin/    # macOS system modules
├── hosts/             # Machine-specific configuration only
│   ├── common/        # Policy shared between machines
│   ├── framework-desktop/  # AMD Framework desktop
│   ├── framework16/        # Framework 16 laptop
│   └── huntress-mbp/       # Apple Silicon MacBook (work)
└── templates/         # Flake templates for new systems
```

## Key Patterns

### Module Structure

Modules are ordinary module files, imported by path. `inputs` arrives through
`specialArgs`, which `flake.nix` sets once:

```nix
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.moduleName;
in
{
  options.stewos.moduleName = {
    enable = lib.mkEnableOption "feature description";
  };

  config = lib.mkIf cfg.enable {
    # configuration
  };
}
```

Take `inputs` only if you actually use it. Because modules are paths, the module
system deduplicates them, so importing the same one twice is harmless.

A module that needs several files gets a directory with a `default.nix`
(`modules/nixos/looking-glass/`, `modules/home-manager/desktop/`). Everything
else is a single `{name}.nix`.

### No Automatic Discovery

Nothing is discovered by scanning directories. To add a module, add a line to
the relevant `modules/{platform}/default.nix`; to add a package, add a line to
`pkgs/default.nix`. This keeps every import greppable.

### Host Configuration

`hosts/{hostname}/` holds configuration only. The outputs are declared in
`flake.nix` using the `mkNixOSHost` / `mkDarwinHost` / `mkHome` helpers defined
there, so the full set of configurations is visible in one file.

`hosts/common/workstation.nix` carries the policy the two Framework machines
share. `system.stateVersion` deliberately stays per-host and must never move
into shared configuration.

### Packages and the Overlay

Packages under `pkgs/` never reference flake inputs. Anything that must come
from an input (a `flake = false` source tree, a colour scheme) is injected into
the scope by `overlays/default.nix` and resolved by argument name. Custom
packages are reached as `pkgs.stewos.<name>`.

The modules expect two overlays on `pkgs`: `stewos.overlays.default` and NUR
(the `firefox` module pulls addons from `pkgs.nur`). `flake.nix` applies both.

## Build Commands

```bash
# Rebuild NixOS system
nh os switch ~/git/stewos

# Rebuild Home-Manager
nh home switch ~/git/stewos

# Test in VM
nix run .#framework-desktop-vm

# Format and verify
nix fmt
nix flake check --all-systems
```

## Adding Components

### New Module

Create `/modules/{platform}/{name}.nix` and add it to that platform's
`default.nix`:
- Use the `stewos.{name}.enable` option pattern
- Wrap config in `lib.mkIf cfg.enable`

### New Package

Create `/pkgs/{name}/default.nix`:
```nix
{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "package-name";
  # ...
}
```
then add `{name} = self.callPackage ./{name} { };` to `/pkgs/default.nix`.

If it needs something from a flake input, add that value to the scope in
`/overlays/default.nix` and take it as an argument here. Set `meta.platforms` on
anything that is not cross-platform, or it will break the `packages` output on
darwin.

### New Host

Create `/hosts/{hostname}/` with `configuration.nix`, `home.nix` and (for NixOS)
`hardware-configuration.nix`, then declare the outputs in `flake.nix`.

## NixOS Modules

| Module | Purpose |
|--------|---------|
| `stewos.base` | Boot loader, Plymouth, Nix settings, `nh`. Enabled by default |
| `stewos.audio` | PipeWire/JACK/ALSA with realtime scheduling |
| `stewos.autologin` | greetd + regreet, straight into a session |
| `stewos.containers` | Docker (Podman is present but commented out) |
| `stewos.desktop-services` | Portals, polkit, graphical session services |
| `stewos.greeter` | Display manager; alternative to `autologin` |
| `stewos.looking-glass` | Looking Glass client; its config is modelled as options |
| `stewos.sshd` | SSH server |
| `stewos.virtualisation` | KVM/QEMU/libvirt + VFIO hooks |
| `stewos.zsa` | udev rules for ZSA keyboards |

`networking.nix`, `security.nix` and `user.nix` have no enable flag and apply
unconditionally. `security.nix` is what disables `sudo` in favour of `doas`;
`user.nix` creates the account described by `stewos.user`.

## Home-Manager Modules

| Module | Purpose |
|--------|---------|
| `stewos.desktop` | Hyprland (Linux) / Aerospace (macOS) and surrounding services |
| `stewos.neovim` | Nixvim configuration with LSP |
| `stewos.zsh` | Shell with Oh-My-Posh |
| `stewos.git` | Git with SSH signing and per-directory identities |
| `stewos.rofi` | Rofi, themed through the RASI DSL |
| `stewos.update-manager` | Tray daemon (`pkgs/update-manager`, Rust): on-demand flake update checks on a worktree branch, prebuilt switch via run0 (system now / next boot / home only), lock bump fast-forwarded into `main` |
| `stewos.embermug-tray` | Ember Mug tray app; a thin wrapper over the `embermug-tray` flake's own home-manager module (`services.embermug-tray`), which owns the unit, package and QSettings file |
| `stewos.alacritty`, `stewos.firefox`, `stewos.bat`, `stewos.eza`, `stewos.zoxide`, `stewos.direnv` | Straightforward per-program modules |

## Desktop Configuration

The directory is split by platform:

```
desktop/
├── options.nix   # the whole stewos.desktop surface, in one file
├── vocabulary.nix# the modifier/action/direction lists the options are typed against
├── default.nix   # imports + cross-platform config + binding shape assertions
├── linux/        # hyprland, style, bindings, theme, polkit, xdg
└── darwin/       # aerospace, karabiner, autoraise, raycast
```

Both platform directories are imported unconditionally and every file guards
its own `config` on `cfg.enable && pkgs.stdenv.is{Linux,Darwin}`. Do not switch
this to conditional `imports` -- deciding what to import from `pkgs.stdenv`
risks a recursion the module system cannot see through.

Options at `stewos.desktop`:
- `monitors` - List of monitor configs (description, resolution, position, scale); Linux
- `keyboards` - Per-keyboard overrides keyed by device name (layout, variant, capsLockEscape); Linux
- `bindings` - Keybindings, keyed by a name of your choosing
- `modifier` - Global keybinding modifier prefix, enum `SUPER`/`ALT`/`CTRL`/`SHIFT` (default `SUPER`)
- `terminal` - Terminal package (default Alacritty)
- `wallpaper` - Path to wallpaper image
- `fonts.ui`, `fonts.monospace` - `{name, package, size}`, shared by every toolkit
- `startLocked` - Bring the session up locked; Linux
- `capsLockEscape` - Send Escape when Caps Lock is pressed
- `swapCommandAlt` - Swap left Command and left Alt; macOS

`lockCommand` still exists but is `internal` -- the platform backend sets it,
no host should.

**The option surface deliberately names no compositor.** A binding is
`{key, modifiers, useModifier, platforms, action | command}` where `key` and
`action` are neutral names. Each backend (`linux/bindings.nix`,
`darwin/aerospace.nix`) owns three tables -- modifiers, keys, actions --
translating those names into its own vocabulary, and asserts on any it does not
implement. Adding an action means adding it to `vocabulary.nix` plus at least
one backend's `actions` table. Keep Hyprland and Rofi vocabulary out of
`options.nix`.

Each backend contributes its default keymap *through* `stewos.desktop.bindings`
with per-field `mkDefault`, which is what lets a host retarget or disable a
StewOS-provided binding by name. Do not go back to merging a private
`defaultBindings` in at render time.

The two keymaps genuinely diverge on `h/j/k/l`: Linux focuses/moves a *window*,
macOS focuses/moves between *monitors*. That is why the vocabulary has separate
window-directional and monitor-directional actions -- it is not redundancy.

The shell UI is `caelestia-shell`, and it owns the pieces a Hyprland setup would
otherwise wire up individually: the locker, idle handling, notifications, the
bar and the wallpaper daemon. There are deliberately no hypridle / hyprlock /
hyprpaper / swaync / waybar modules here -- do not add them back without
checking whether caelestia already covers it.

`stewos.rofi` is still a real module and is enabled per-host; caelestia does not
replace the launcher.

All application theming lives in `modules/home-manager/desktop/linux/theme.nix`
and is driven from `config.colorScheme` (nix-colors), so a scheme change moves
the whole desktop rather than half of it:

- GTK 3 and 4 via `adw-gtk3-dark` plus a generated `@define-color` stylesheet
  set as both `gtk3.extraCss` and `gtk4.extraCss`. libadwaita ignores theme
  packages but honours those named colours, and adw-gtk3 backports them to
  GTK 3 -- which is why one stylesheet covers both.
- `hypr/hyprtoolkit.conf` for hyprtoolkit-native apps.
- `programs.hyprland-qt-support` for the QML style hyprpolkitagent uses.
- `hypr/hyprqt6engine.conf` for every other Qt6 app, with `qt.platformTheme.name
  = "hyprqt6engine"` (`pkgs.stewos.hyprqt6engine`) instead of qt6ct/gtk3. Its
  palette is a **generated** qt5ct-format file -- three rows of 22 `#AARRGGBB`
  values in `QPalette::ColorRole` order -- not a path into a theme package.
  The package is the upstream flake's, rebuilt against the Qt stdenv: upstream
  builds the plugin with `gcc16Stdenv` and it then cannot be loaded by a
  nixpkgs Qt app at all. See "Qt apps lose every themed icon" below.

The one thing not derived is cursors and tinted folder icons, which ship as
per-flavour image sets. Those come from a small `schemeAssets` map in
`theme.nix` keyed on `config.colorScheme.slug`, with a neutral fallback so an
unmapped scheme still evaluates. That map is the right home for them: `pkgs/`
is for derivations and `lib/` takes a pkgs-free nixpkgs lib, so neither can
return a package.

Stylix is imported (`modules/home-manager/default.nix`, and the NixOS and
Darwin equivalents) but **deliberately never configured**. Adopting it would
mean handing it Alacritty, Neovim, Firefox, GTK, Qt and the cursor -- all styled
by hand here -- and giving the repo a second palette source alongside
`config.colorScheme`. Do not wire it up as a drive-by.

## Conventions

- **Privilege escalation**: Uses `doas` instead of `sudo`
- **Git**: SSH URLs forced for GitHub, SSH key signing
- **State versions**: `system.stateVersion` is per-host (in `hosts/*/configuration.nix`);
  Home-Manager's 25.05 is shared in `modules/home-manager/default.nix`
- **Formatting**: `nix fmt` (nixfmt-tree)
- **Platform conditionals**: Use `lib.mkIf pkgs.stdenv.isLinux`
- **Defaults**: Use `lib.mkDefault` for overridable values
- **Experimental features**: `nix-command` and `flakes` enabled

## Consuming StewOS Elsewhere

`nixosModules.default`, `homeModules.default` and `darwinModules.default` are
paths to the module trees. They reference StewOS's own inputs from inside
`imports`, where only `specialArgs` work, so consumers must pass them back:

```nix
specialArgs = { inputs = stewos.lib.moduleInputs; };
```

Consequently `inputs` inside a StewOS module always means StewOS's inputs, never
the consumer's. `templates/nixos-single/` is a worked example.

## Flake Inputs

### Core Infrastructure
- `nixpkgs` (nixos-unstable) - Main package repository
- `nixpkgs-darwin` (nixpkgs-26.05-darwin) - macOS packages
- `home-manager` (master) - User configuration
- `nix-darwin` (nix-darwin-26.05) - macOS system management

### Desktop/Theming
- `stylix` (release-26.05) - Unified theming engine
- `nix-colors` - Color scheme management
- `nixvim` - Neovim as Nix modules
- `hyprsplit` - Hyprland workspace splitting plugin

### System Tools
- `lanzaboote` - Secure Boot support
- `nh` - Simplified Nix rebuilding
- `nixos-hardware` - Hardware configurations
- `mac-app-util` - macOS app trampolines for Home-Manager

### Personal Flakes (github:calebstewart)
- `embermug-tray` - Ember Mug system tray app

### External Custom Flakes
- `caelestia-shell` (github:caelestia-dots/shell) - Shell UI framework
- `caelestia-cli` (github:Gitkubikon/cli) - CLI for the above
- `llm-agents` (github:numtide/llm-agents.nix) - Source of `claude-code`; see
  the failure mode below
- `vfio-hooks` (github:PassthroughPOST/VFIO-Tools) - GPU passthrough tools
- `gh-actions-language-server` (github:lttb/gh-actions-language-server) - GitHub Actions LSP
- `hyprqt6engine` (github:hyprwm/hyprqt6engine) - Qt6 platform theme; unreleased
  upstream and carries the same `follows` fragility as `llm-agents` (same
  remedy: drop the follows if it stops building after a flake update). Consumed
  as `pkgs.stewos.hyprqt6engine`, which rebuilds it against the Qt stdenv
  (`pkgs/hyprqt6engine/`)
- `hyprpolkitagent` (github:hyprwm/hyprpolkitagent) - Polkit agent from
  upstream because nixpkgs' 0.1.3 predates the hyprtoolkit rewrite (upstream
  did not bump the version); same follows caveat as `hyprqt6engine`. Consumed
  as `pkgs.stewos.hyprpolkitagent`, which carries a local rendering patch
  (`pkgs/hyprpolkitagent/`)

### Community
- `nur` - Nix User Repository
- `nix-std` - Standard library extensions

## Known Failure Modes

### claude-code fails to build after a flake update

`claude-code` comes from the `llm-agents` input rather than nixpkgs, because
nixpkgs lags upstream releases. That input carries
`inputs.nixpkgs.follows = "nixpkgs"` so it does not pull a second nixpkgs tree
into the lock, and it built cleanly that way when it was added
(claude-code 2.1.228, verified by building it and running the binary).

The follows is the fragile part. `llm-agents` pins its own nixpkgs and builds
through `bun2nix` against it, so it is only ever tested against that pin. A
`nix flake update` can move either side and leave claude-code building against
a nixpkgs its packaging never saw.

**Symptom:** `claude-code` fails to build — most likely inside `bun2nix` or the
bun/node derivation underneath it — while nothing in this repository changed
and every other package still builds.

**Fix:** drop the follows in `flake.nix` and let the flake use its own pin:

```nix
llm-agents.url = "github:numtide/llm-agents.nix";
```

That adds a second nixpkgs to `flake.lock`, which is the correct trade — the
follows is a lock-size optimization, not a requirement. Do not try to fix it by
patching the package or pinning `llm-agents` to an older revision; the whole
point of the input is that it tracks upstream.

### Qt apps lose every themed icon

**Symptom:** Qt apps render the broken-image placeholder wherever they draw an
icon by freedesktop name — the caelestia tray, notification icons, menu icons.
Icons supplied as pixmaps or absolute paths (an SNI app shipping its own) still
work, which makes it look like the icon theme is at fault. It is not: the theme
is installed and the names resolve on disk.

**Cause:** the `hyprqt6engine` platform theme plugin failed to load, so Qt has
no `QPlatformTheme::SystemIconThemeName` hint, `QIcon::themeName()` is empty and
*every* `QIcon::fromTheme` call in the process returns null. Nothing reports
this; Qt logs the load failure only under `QT_DEBUG_PLUGINS=1`.

The usual reason is a libstdc++ ABI split. A `platformthemes` plugin is
`dlopen`'d into a host that already has a `libstdc++.so.6` mapped, and the
loader matches on SONAME rather than the plugin's RPATH — so the plugin gets the
*host's* copy. nixpkgs builds its whole Qt stack with the default stdenv while
the Hypr packages are pinned to `gcc16Stdenv`, and upstream's overlay pins the
plugin the same way, so it asks gcc 15's libstdc++ for `GLIBCXX_3.4.36` and
never loads.

**Diagnose:**

```bash
QT_DEBUG_PLUGINS=1 <any qt6 app> 2>&1 | rg -i "hyprqt6engine|cannot load"
```

**Fix:** `pkgs/hyprqt6engine` already rebuilds the plugin — plus `hyprlang` and
`hyprutils`, which leak the same symbol version — against
`qt6Packages.qtbase.stdenv`. If a flake update reintroduces the failure, check
that override still applies rather than reaching for a different platform theme.
Deriving the stdenv from qtbase rather than naming a gcc version is deliberate:
it stays correct as nixpkgs moves its Qt stack forward. `pkgs/hyprqt6engine/
upstream-issue.md` is the report to file if this is still unfixed upstream.
