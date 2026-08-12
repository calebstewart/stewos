# StewOS - NixOS and Nix-Darwin Configurations
This repository houses my personal NixOS, Nix-Darwin and Home-Manager configurations for all my systems.
It also houses some utility library functions, and a few custom packages which are used for my system
configurations.

Generally, the system is configured with fields under `stewos.*`. The majority of configuration comes
from `stewos.desktop` which will configure Hyprland and my custom [stew-shell] shell UI and associated
services (`hyprlock`, `swaync`, etc.) for NixOS. For Nix-Darwin, `stewos.desktop` configures Aerospace
and associated services for customizing the graphical interface in MacOS.

## Quick Start

To get started with StewOS on a new NixOS system:

```bash
# Create a new configuration from the template
nix flake new -t github:calebstewart/stewos#nixos-single ./my-config
cd my-config

# Initialize git and add files
git init
git add .

# Copy your hardware configuration (generated during NixOS install)
cp /etc/nixos/hardware-configuration.nix .
git add hardware-configuration.nix

# Edit flake.nix with your hostname and user info
# Then rebuild your system
nixos-rebuild switch --flake .#your-hostname
```

## Initial Setup on a New System

### Prerequisites
- NixOS installed with a base configuration
- Nix flakes enabled (add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf`)

### Step-by-Step Setup

1. **Create your configuration** using the StewOS template:
   ```bash
   nix flake new -t github:calebstewart/stewos#nixos-single ~/git/stewos
   cd ~/git/stewos
   ```

2. **Initialize git** (required for flakes):
   ```bash
   git init
   git add .
   ```

3. **Copy your hardware configuration**:
   ```bash
   cp /etc/nixos/hardware-configuration.nix .
   git add hardware-configuration.nix
   ```

4. **Edit `flake.nix`** and set your:
   - Hostname
   - Username
   - Full name
   - Email address

5. **Edit `src/configuration.nix`** to enable the StewOS modules you want.

6. **Edit `src/home.nix`** to configure Home-Manager modules.

7. **Build and switch**:
   ```bash
   # First time (before nh is available)
   sudo nixos-rebuild switch --flake .#your-hostname

   # Subsequent rebuilds (after nh is installed)
   nh os switch ~/git/stewos
   nh home switch ~/git/stewos
   ```

## Repository Layout

```
flake.nix     Inputs, and every output declared explicitly. The single place
              where flake inputs are captured and handed to the module system.
overlays/     The StewOS overlay: adds a "stewos" package scope to nixpkgs.
              Exported as overlays.default.
pkgs/         Package definitions. Plain callPackage derivations that never
              reference flake inputs.
lib/          Pure helpers (the RASI DSL, Hyprland generators). Takes a nixpkgs
              lib, returns functions.
modules/      Reusable modules, one file per module.
  common/       Options shared by NixOS and home-manager.
  nixos/        NixOS modules. default.nix lists them all.
  home-manager/ Home-Manager modules.
  nix-darwin/   Nix-Darwin modules.
hosts/        Per-machine configuration. Configuration only -- flake.nix owns
              the output shape.
templates/    Starting points for new StewOS-based flakes.
```

Modules are ordinary module files. They take `{ inputs, lib, config, pkgs, ... }`
and are imported by path, so `imports = [ ./audio.nix ]` works and the module
system deduplicates them normally. Nothing is auto-discovered by scanning
directories: to add a module, add a line to the relevant `default.nix`.

## Defining a System

Add a directory under [hosts/] with the machine's configuration, then declare
the outputs in `flake.nix`:

```nix
nixosConfigurations.my-host = mkNixOSHost {
  hostname = "my-host";
  system = "x86_64-linux";
  user = caleb;
  modules = [
    ./hosts/my-host/hardware-configuration.nix
    ./hosts/my-host/configuration.nix
  ];
};

homeConfigurations."caleb@my-host" = mkHome {
  system = "x86_64-linux";
  user = caleb;
  homeDirectory = "/home/caleb";
  modules = [ ./hosts/my-host/home.nix ];
};
```

`mkNixOSHost`, `mkDarwinHost` and `mkHome` are defined in `flake.nix` itself --
they are thin wrappers that attach the StewOS modules, the shared `pkgs`
instance for that system, and `inputs` via `specialArgs`.

Every NixOS host gets a `nix run .#<hostname>-vm` app for booting that
configuration in a VM.

## Using StewOS From Another Flake

The modules are exported, but they are written against StewOS's own inputs and
reference them inside `imports`, where only `specialArgs` are available. So pass
them back in via the exported `moduleInputs`:

```nix
nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
  specialArgs = { inputs = stewos.lib.moduleInputs; };
  modules = [ stewos.nixosModules.default ./configuration.nix ];
};
```

This means `inputs` inside a StewOS module always refers to StewOS's inputs;
pass your own under a different name. See [templates/nixos-single/src/flake.nix]
for a complete example.

The modules also expect two overlays on the `pkgs` you hand them: StewOS's own
package scope, and NUR, which the `firefox` module uses for browser addons.

```nix
pkgs = import nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    stewos.overlays.default                          # pkgs.stewos.*
    stewos.lib.moduleInputs.nur.overlays.default     # pkgs.nur.*
  ];
};
```

If you only want the packages and none of the modules, `overlays.default` on its
own is enough.

## Available Modules

### NixOS Modules

These modules are enabled under `stewos.*` in your NixOS configuration:

| Module | Description |
|--------|-------------|
| `user` | User account creation with groups and shell configuration |
| `audio` | PipeWire, JACK, ALSA, and NoiseTorch audio configuration |
| `networking` | NetworkManager, firewall, and Bluetooth configuration |
| `sshd` | SSH server configuration |
| `containers` | Docker with rootless support |
| `virtualisation` | KVM/QEMU/libvirt with VFIO hooks for GPU passthrough |
| `security` | Security hardening options |
| `desktop-services` | Polkit and common desktop services |
| `autologin` | Automatic login support |
| `greeter` | Display manager (greetd/tuigreet) configuration |
| `zsa` | ZSA keyboard (Moonlander, Voyager, etc.) support |
| `looking-glass` | Looking Glass VM display client support |

### Home-Manager Modules

These modules are enabled under `stewos.*` in your Home-Manager configuration:

| Module | Description |
|--------|-------------|
| `desktop` | Hyprland (Linux) / Aerospace (macOS) desktop environment |
| `neovim` | Full Neovim configuration via nixvim with LSP support |
| `zsh` | Zsh shell with Oh-My-Posh prompt |
| `git` | Git with SSH signing and conditional configuration |
| `alacritty` | Terminal emulator configuration |
| `firefox` | Firefox browser configuration |
| `rofi` | Application launcher (Linux) |
| `bat` | Syntax-highlighted cat replacement |
| `eza` | Modern ls replacement |
| `zoxide` | Smart directory navigation (z/cd replacement) |
| `direnv` | Per-directory development environment management |

## Available Packages

Custom packages live in the `stewos` scope, reachable as `pkgs.stewos.<name>`
once the overlay is applied, and as `nix build .#<name>`:

| Package | Description |
|---------|-------------|
| `gh-actions-language-server` | LSP for GitHub Actions workflow files |
| `lucas-chess` | Lucas Chess R2 |
| `shortcut-cli` | Command line client for shortcut.com |
| `wl-gen-uuid` | Wayland UUID generation utility |
| `rofi-theme` | StewOS Rofi theme |
| `rofi-hyprpower` | Rofi power menu script mode |
| `rofi-libvirt` | Rofi libvirt VM script mode |

The scope also contains the `mkRofiConfig` and `mkRofiTheme` builders. They are
functions rather than derivations, so they are not part of the `packages`
output.

## Terminal Configuration
The terminal for both NixOS and Nix-Darwin is Alacritty. The color scheme for Alacritty is defined by
the root `colorScheme` configuration. For the existing systems, I generally use `catpuccin-mocha`.
The default shell is `zsh` for all systems.

<img width="2131" height="1123" alt="image" src="https://github.com/user-attachments/assets/3d9ffb51-4ef8-4122-8a9c-522773afaa6b" />

## Neovim Configuration
If you enable `stewos.neovim.enable`, then StewOS will configure Neovim using [nixvim]. There are a lot
of moving parts in vim configurations, so I won't go into all the details, but the improtant big pieces
are:

1. Configured to use the color scheme defined in the root `colorScheme` config.
2. Use ` ` (SPACE) as the global leader, which behaves similarly to emacs.
3. Enable support for `wl-copy` under NixOS (ignored for Nix-Darwin).
4. Enable plugins: `nix`, `lualine`, `lsp-format`, `oil`, `cmp-nvim-lsp-signature-help`, `transparent`, `noice`, `neogit`, `vim-bbye`, `illuminate`, `web-devicons`, `treesitter`, `markdown-preview`, `trouble`, `notify`, `toggleterm`, `lspsaga`, `lsp`, `cmp`, `none-ls`, `telescope`, `neotree`, `which-key`.
5. LSP Servers: `lua_ls`, `gopls`, `nixd`, `pyright`, `clangd`, `jdtls`, `ts_ls`, `vala_ls`, `mesonlsp`, `ruby_lsp`, `rust_analyzer`, `gh_actions_ls`.
6. A bunch of keymaps with helpful documentation.

<img width="3826" height="2104" alt="image" src="https://github.com/user-attachments/assets/2651791c-c14e-4a41-87fd-9f40a92eaa9e" />

[hosts/]: ./hosts
[templates/nixos-single/src/flake.nix]: ./templates/nixos-single/src/flake.nix
[stew-shell]: https://github.com/calebstewart/stew-shell
[nixvim]: https://github.com/nix-community/nixvim
