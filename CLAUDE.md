# StewOS

A declarative Nix Flake-based configuration management system for NixOS, Nix-Darwin (macOS), and Home-Manager. Manages multiple machines with a unified, modular approach.

## Project Structure

```
stewos/
├── flake.nix          # Inputs + every output, declared explicitly.
│                      # The only place flake inputs are captured.
├── overlays/          # The StewOS overlay (adds pkgs.stewos.*)
├── pkgs/              # Package definitions; plain callPackage derivations
│   └── default.nix    # Explicit list of every package in the scope
├── lib/               # Pure helpers: takes a nixpkgs lib, returns functions
│   ├── hypr.nix       # Hyprland helpers (monitors, keybindings, rofi)
│   └── rasi/          # RASI DSL for Rofi theme generation
├── modules/
│   ├── common/        # Options shared by NixOS and Home-Manager
│   ├── nixos/         # NixOS system modules (default.nix lists them)
│   ├── home-manager/  # Home-Manager user modules
│   └── nix-darwin/    # macOS system modules
├── hosts/             # Machine-specific configuration only
│   ├── framework-desktop/  # AMD Framework desktop
│   ├── framework16/        # Framework laptop
│   └── huntress-mbp/       # Apple Silicon MacBook
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

### No Automatic Discovery

Nothing is discovered by scanning directories. To add a module, add a line to
the relevant `modules/{platform}/default.nix`; to add a package, add a line to
`pkgs/default.nix`. This keeps every import greppable.

### Host Configuration

`hosts/{hostname}/` holds configuration only. The outputs are declared in
`flake.nix` using the `mkNixOSHost` / `mkDarwinHost` / `mkHome` helpers defined
there, so the full set of configurations is visible in one file.

### Packages and the Overlay

Packages under `pkgs/` never reference flake inputs. Anything that must come
from an input (a `flake = false` source tree, a colour scheme) is injected into
the scope by `overlays/default.nix` and resolved by argument name. Custom
packages are reached as `pkgs.stewos.<name>`.

## Build Commands

```bash
# Rebuild NixOS system
nh os switch ~/git/stewos

# Rebuild Home-Manager
nh home switch ~/git/stewos

# Test in VM
nix run .#framework-desktop-vm
```

## Adding Components

### New Module

Create `/modules/{platform}/{name}/default.nix`:
- Use `stewos.{name}.enable` option pattern
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
`/overlays/default.nix` and take it as an argument here.

### New Host

Create `/hosts/{hostname}/` with `configuration.nix`, `home.nix` and (for NixOS)
`hardware-configuration.nix`, then declare the outputs in `flake.nix`.

## Key Modules

| Module | Platform | Purpose |
|--------|----------|---------|
| `stewos.user` | NixOS | User account creation |
| `stewos.audio` | NixOS | PipeWire/JACK audio |
| `stewos.containers` | NixOS | Podman/Docker |
| `stewos.virtualisation` | NixOS | KVM/QEMU |
| `stewos.desktop` | Home-Manager | Hyprland, Waybar, Rofi |
| `stewos.neovim` | Home-Manager | Nixvim configuration |
| `stewos.zsh` | Home-Manager | Shell with Oh-My-Posh |
| `stewos.git` | Home-Manager | Git with SSH signing |

## Desktop Configuration

Desktop module options at `stewos.desktop`:
- `monitors` - List of monitor configs (resolution, position, scale)
- `idle.{dim,lock,sleep}` - Timeout values in seconds
- `keybindings` - Hyprland keybindings
- `wallpaper` - Path to wallpaper image

## Conventions

- **Privilege escalation**: Uses `doas` instead of `sudo`
- **Git**: SSH URLs forced for GitHub, SSH key signing
- **State versions**: `system.stateVersion` is per-host (in `hosts/*/configuration.nix`);
  Home-Manager 25.05 is shared
- **Formatting**: `nix fmt` (nixfmt-tree)
- **Platform conditionals**: Use `lib.mkIf pkgs.stdenv.isLinux`
- **Defaults**: Use `lib.mkDefault` for overridable values
- **Experimental features**: `nix-command` and `flakes` enabled

## Flake Inputs

### Core Infrastructure
- `nixpkgs` (nixos-25.11) - Main package repository
- `nixpkgs-unstable` - Latest packages
- `nixpkgs-darwin` (25.05-darwin) - macOS packages
- `home-manager` (release-25.11) - User configuration
- `nix-darwin` (25.05) - macOS system management

### Desktop/Theming
- `stylix` - Unified theming engine
- `nix-colors` - Color scheme management
- `nixvim` - Neovim as Nix modules

### System Tools
- `lanzaboote` - Secure Boot support
- `nixos-generators` - Image generation
- `nh` - Simplified Nix rebuilding
- `nixos-hardware` - Hardware configurations

### Personal Flakes (github:calebstewart)
- `stew-shell` - Custom shell UI components
- `embermug-tray` - Ember Mug system tray app

### External Custom Flakes
- `caelestia-shell` (github:caelestia-dots/shell) - Shell UI framework
- `vfio-hooks` (github:PassthroughPOST/VFIO-Tools) - GPU passthrough tools
- `gh-actions-language-server` (github:lttb/gh-actions-language-server) - GitHub Actions LSP

### Community
- `nur` - Nix User Repository
- `nix-std` - Standard library extensions
- `flake-utils` - Flake utilities
