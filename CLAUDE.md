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
| `stewos.update-manager` | Tray daemon (`pkgs/update-manager`, Rust): on-demand flake update checks on a worktree branch, prebuilt switch via run0 (system now / next boot / home only), lock bump fast-forwarded into `main`. Ships its own status icons -- see below |
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

Unlocking the screen also unlocks the GNOME login keyring. The hosts autologin,
so greetd never collects a password and the `pam_gnome_keyring` lines NixOS puts
in `/etc/pam.d/login` have nothing to work with -- the lock screen is the only
place in the session a password is typed. Two pieces make it work, and both are
load-bearing:

- `pkgs/caelestia-shell` appends `auth optional pam_gnome_keyring.so` to the
  locker's PAM stack. Caelestia reads that stack from *inside the package*
  (`modules/lock/Pam.qml` points Quickshell's `PamContext` at
  `shellDir + "/assets/pam.d"`), not `/etc/pam.d`, which is why this is a
  packaging override rather than an upstream patch. Quickshell calls only
  `pam_authenticate` -- no `pam_setcred`, no session phase -- which works
  because `pam_gnome_keyring` unlocks from `pam_sm_authenticate` itself.
- `stewos.desktop-services` starts the keyring's secrets component up front.
  Without that the unlock loses a race; see the failure mode below.

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

### update-manager icons

The update-manager daemon borrows no freedesktop icon names at all. It ships
nine of its own: six status badges (idle, checking, up-to-date,
updates-available, applying, error) and three menu glyphs (search, apply, quit).
Nothing is looked up by name, which is also why they survive the Qt
platform-theme failure described under "Qt apps lose every themed icon":

- the tray icon goes out as an SNI **pixmap** (ARGB32, big-endian), with
  `IconName` deliberately left empty -- a host prefers the name whenever it can
  resolve one, so setting both would mean our art is never drawn;
- menu entries go out as dbusmenu **`icon-data`** (raw PNG), with `icon-name`
  empty for the same reason;
- notifications get an **absolute path** to the 64px PNG.

**The six status icons share one silhouette: an arrow landing on a baseline.**
That mark is the identity and must stay in every state -- a tray icon's first
job is to say *which daemon* it belongs to, and an earlier draft that used a
plain ring as the constant element failed at exactly that (a ring plus a
checkmark is indistinguishable from any VPN or sync indicator). State is carried
by three channels layered on top:

| Channel | Values |
|---|---|
| arrowhead | stroked (settled) / solid (wants attention) |
| baseline | solid (settled) / `4 2` dashed (busy) |
| colour | one `base16` slot per state |

Two consequences worth knowing before editing the art. The baseline sits at the
same `y` in every state on purpose, so the glyph does not visibly jump when the
daemon changes state. And `idle` and `up-to-date` are deliberately the same
shape, separated only by hue -- both mean "nothing to do", and `idle` only
exists until the first check runs. `error` is the single state that breaks the
pattern: the arrow shrinks to ~70% to make room for an exclamation, which is
worth the lost size there and nowhere else.

`pkgs/update-manager-icons/` holds the SVG sources -- one 24px grid, all strokes
`currentColor` -- and rasterizes them with `resvg --stylesheet`, one colour per
argument (the six states are `Status` context, the menu glyphs are `Actions`):

```nix
pkgs.stewos.update-manager-icons.override { error = "#ff0000"; }
```

It is a **separate derivation from the daemon on purpose**. The daemon takes the
rendered tree as a runtime path (`--icon-dir`), so a recolour re-realizes one
`runCommand`; folding the store path into `pkgs/update-manager`'s wrapper would
put it in that derivation's `postFixup` and make every palette change -- every
host on a different scheme -- recompile the Rust crate.

The colours themselves are module options
(`stewos.update-manager.icons.<state>`), each defaulting to a `base16` slot of
`config.colorScheme.palette`, because `pkgs/` may not read `config` and the
module may. `stewos.update-manager.iconPackage` is the escape hatch, and it is
the one that matters while the module is enabled: the unit always passes
`--icon-dir`, so overriding `update-manager-icons` on `package` only changes the
binary's standalone default.

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
- `caelestia-shell` (github:caelestia-dots/shell) - Shell UI framework. Consumed
  as `pkgs.stewos.caelestia-shell`, which appends `pam_gnome_keyring` to the
  locker's PAM stack (`pkgs/caelestia-shell/`). Note it overrides the flake's
  `with-cli` output, not `default` -- that is what the upstream home-manager
  module defaults to, and `cli.enable` is set here
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

### The lock screen says the keyring password is invalid

**Symptom:** unlocking the screen leaves the login keyring locked, and the
journal has `gkr-pam: the password for the login keyring was invalid`. The
password is not wrong -- `pam_unix` accepted the very same string a moment
earlier, which is why the session unlocked at all. Anything wanting a secret
then prompts separately, and that prompt takes the same password happily.

**Cause:** a race, not a credential problem. PAM's `auto_start` brings up
`gnome-keyring-daemon --login`, which owns no well-known bus name and does not
run the *secrets* component. That component only appears when something first
asks for `org.freedesktop.secrets` and D-Bus activates gnome-keyring a second
time; the new process finds the first (`discover_other_daemon`), hands the work
over, and -- because the activation file passes `--foreground` -- sits parked
for the rest of the session. With autologin and `startLocked`, the lock screen
comes up before anything has asked for a secret, so the unlock reaches a daemon
that cannot service it. A boot where this went wrong:

```
19:35:44  gnome-keyring-daemon --login  (PAM auto_start, at greetd)
19:35:52  gkr-pam: the password for the login keyring was invalid
19:36:00  secrets component activated over D-Bus
19:36:06  gcr prompt unlocks it with the same password
```

**Fix:** already in place -- `stewos.desktop-services` defines a
`gnome-keyring-secrets` user unit that runs
`gnome-keyring-daemon --start --components=secrets` before
`graphical-session.target`. Dropping `--foreground` matters: the command exits 0
once the handoff is done, so `Type = "oneshot"` gives a real readiness barrier,
whereas home-manager's own `services.gnome-keyring` module uses the foreground
form under `Type = simple` and is considered started the instant it forks --
which would not close this race. Owning the bus name early also stops the D-Bus
activation firing at all, so the parked stub never appears.

**Verify:** after a reboot, all three should hold.

```bash
systemctl --user status gnome-keyring-secrets   # active (exited)
journalctl -b | rg gkr-pam                      # unlocked login keyring
pgrep -af gnome-keyring                         # only --daemonize --login
```

Do not chase this as a wrong password. If the keyring genuinely has a different
password the message is identical, so check the ordering above first.

### Darwin home configuration pairs home-manager master with stable nixpkgs

`home-manager` tracks master while `nixpkgs-darwin` tracks the
`nixpkgs-*-darwin` release branch, so the darwin home configurations
(currently `huntress-mbp`) build with mismatched versions — e.g. home-manager
26.11 against nixpkgs 26.05. The Linux hosts are unaffected because they build
from `nixos-unstable`, which is what home-manager master targets.

This skew is deliberate (a stable home-manager would lag the modules the Linux
hosts use), and home-manager's release-check warning is suppressed on the
affected host with `home.enableNixpkgsReleaseCheck = false` in
`hosts/huntress-mbp/home.nix`.

**Symptom:** after a flake update, the darwin home configuration fails to
evaluate or behaves oddly — typically a renamed/removed nixpkgs option or a
home-manager module using a package attribute that stable nixpkgs does not
have yet — while the Linux hosts and the darwin *system* configuration are
fine. Because the warning is suppressed, nothing will point at the version
skew; check for it before debugging the module itself.

**Fix:** usually wait for (or pin to) a home-manager revision compatible with
the darwin release branch, or bump `nixpkgs-darwin` to the next release. As a
last resort, split the input and pin a separate `home-manager` release branch
for darwin.
