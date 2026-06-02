# StewOS

A declarative Nix Flake-based configuration management system for NixOS, Nix-Darwin (macOS), and Home-Manager. Manages multiple machines with a unified, modular approach.

## Project Structure

```
stewos/
├── flake.nix          # Main flake configuration
├── lib/               # Utility library functions
│   ├── default.nix    # mkNixOSSystem, mkNixDarwinSystem, mkHomeManagerConfig, etc.
│   ├── hypr.nix       # Hyprland helpers (monitors, keybindings, rofi)
│   └── rasi/          # RASI DSL for Rofi theme generation
├── modules/
│   ├── nixos/         # NixOS system modules
│   ├── home-manager/  # Home-Manager user modules
│   └── nix-darwin/    # macOS system modules
├── packages/          # Custom package definitions
├── systems/           # Machine-specific configurations
│   ├── framework-desktop/  # AMD Framework 16 + NVIDIA
│   ├── framework16/        # Framework laptop
│   └── huntress-mbp/       # Apple Silicon MacBook
└── templates/         # Flake templates for new systems
```

## Key Patterns

### Module Structure

All modules follow this pattern:

```nix
{ inputs... }:
{
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

### Automatic Discovery

Modules and packages are auto-imported via directory structure:
- `/modules/{platform}/{name}/default.nix` becomes a module
- `/packages/{name}/default.nix` becomes a package overlay

### System Configuration

Systems in `/systems/{hostname}/default.nix` return flake outputs:

```nix
{
  hostname,
  stewos,
  ...
}@inputs:
let
  system = "x86_64-linux";
  user = stewos.lib.mkUserOptions { username = "caleb"; ... };
in
{
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem { ... };
  homeConfigurations."${user.username}@${hostname}" = stewos.lib.mkHomeManagerConfig { ... };
}
```

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

Create `/packages/{name}/default.nix`:
```nix
{
  lib,
  stdenv,
  ...
}:
stdenv.mkDerivation {
  pname = "package-name";
  # ...
}
```

### New System

Create `/systems/{hostname}/` with:
- `default.nix` - Flake outputs
- `configuration.nix` - NixOS config
- `home.nix` - Home-Manager config

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
- **State versions**: NixOS 24.05, Home-Manager 25.05
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
