# StewOS

Personal NixOS, Nix-Darwin and Home-Manager configuration for all my machines,
plus the modules, packages and helper libraries they are built from.

Everything is configured through options under `stewos.*`. Most of the surface
area is `stewos.desktop`, which sets up Hyprland and its associated services
(locking, notifications, wallpaper, bar) on NixOS, and Aerospace with the
equivalent macOS pieces on Nix-Darwin.

## Repository Layout

```
flake.nix     Inputs, and every output declared explicitly. The one place
              flake inputs are captured and handed to the module system.
overlays/     The StewOS overlay: adds a "stewos" package scope to nixpkgs.
pkgs/         Package definitions. Plain callPackage derivations that never
              reference flake inputs.
lib/          Pure helpers: takes a nixpkgs lib, returns functions.
  desktop.nix   Command line construction shared by both desktop backends
  rofi.nix      Rofi command line construction
  rasi/         RASI DSL used to generate Rofi themes and configs
modules/
  common/       Options shared by NixOS and Home-Manager
  nixos/        NixOS modules; default.nix lists them all
  home-manager/ Home-Manager modules
  nix-darwin/   Nix-Darwin modules
hosts/        Per-machine configuration, and nothing else
  common/       Policy shared between machines
templates/    Starting points for new StewOS-based flakes
```

Two rules keep this navigable:

**Nothing is auto-discovered.** Modules and packages are listed explicitly in
the relevant `default.nix`. Adding one is a single line, and in exchange every
import is greppable and the set of modules is visible without evaluating
anything.

**Modules are ordinary module files.** They take
`{ inputs, lib, config, pkgs, ... }` and are imported by path, so
`imports = [ ./audio.nix ]` works and the module system deduplicates them
normally. `inputs` arrives once, through `specialArgs` set in `flake.nix`.

## Machines

| Host | Platform | Notes |
|------|----------|-------|
| `framework-desktop` | `x86_64-linux` | AMD Framework Desktop, Secure Boot, ollama, tailscale |
| `framework16` | `x86_64-linux` | Framework 16 laptop, Secure Boot |
| `huntress-mbp` | `aarch64-darwin` | Apple Silicon MacBook, work machine |

The two Framework machines share `hosts/common/workstation.nix`, which holds the
Secure Boot setup, silent boot, sleep settings and the StewOS modules they both
run. Anything genuinely machine-specific stays in that machine's
`configuration.nix`, including `system.stateVersion`, which must never follow a
shared default.

## Building

```bash
# NixOS
nh os switch ~/git/stewos

# Home-Manager
nh home switch ~/git/stewos

# Boot a host's configuration in a VM
nix run .#framework-desktop-vm

# Format, and check that everything still evaluates
nix fmt
nix flake check --all-systems
```

## Adding to the Repository

**A module.** Create `modules/{platform}/{name}.nix` following the usual shape,
then add it to that platform's `default.nix`:

```nix
{ lib, config, ... }:
let
  cfg = config.stewos.thing;
in
{
  options.stewos.thing.enable = lib.mkEnableOption "thing";

  config = lib.mkIf cfg.enable {
    # ...
  };
}
```

Only take `inputs` if you actually use it.

**A package.** Create `pkgs/{name}/default.nix` as a plain callPackage
derivation and add a line to `pkgs/default.nix`. Packages never reference flake
inputs; if one needs something from an input (a `flake = false` source tree, a
colour scheme), add that value to the scope in `overlays/default.nix` and take
it as an argument.

**A machine.** Create `hosts/{hostname}/` with `configuration.nix`, `home.nix`
and, for NixOS, `hardware-configuration.nix`. Then declare the outputs in
`flake.nix`:

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
  modules = [ ./hosts/my-host/home.nix ];
};
```

`mkNixOSHost`, `mkDarwinHost` and `mkHome` live in `flake.nix`. They are thin
wrappers that attach the StewOS modules, the shared `pkgs` instance for that
system, and `inputs` via `specialArgs`. `mkHome` derives the home directory from
the username, so the two cannot disagree.

## NixOS Modules

Enabled under `stewos.*` in a NixOS configuration.

| Module | Description |
|--------|-------------|
| `base` | Boot loader, Plymouth, Nix settings, `nh`, documentation. On by default; set `enable = false` to take the modules without the opinions |
| `audio` | PipeWire, JACK, ALSA and realtime scheduling |
| `autologin` | greetd with regreet, logging straight into a session |
| `containers` | Docker, with Compose and Docker compatibility options |
| `desktop-services` | Portals, polkit and the services a graphical session needs |
| `greeter` | Display manager, as an alternative to `autologin` |
| `looking-glass` | Looking Glass client for VM display passthrough, with the client config modelled as options |
| `sshd` | SSH server, with address and port options |
| `virtualisation` | KVM/QEMU/libvirt, plus VFIO hooks for GPU passthrough |
| `zsa` | udev rules for ZSA keyboards, and the keymapp editor |

`networking`, `security` and `user` have no enable flag -- they apply
unconditionally as part of the module set. `security` is what replaces `sudo`
with `doas`; `user` creates the account described by `stewos.user`.

## Home-Manager Modules

Enabled under `stewos.*` in a Home-Manager configuration.

| Module | Description |
|--------|-------------|
| `desktop` | Hyprland (Linux) or Aerospace (macOS), and everything around them |
| `neovim` | Neovim via nixvim, with LSP, completion and a full keymap set |
| `zsh` | Zsh with Oh-My-Posh, any-nix-shell and completion |
| `git` | Git with SSH signing and per-directory identities |
| `rofi` | Rofi launcher, themed through the RASI DSL |
| `update-manager` | Tray daemon that checks for flake updates, prebuilds them on a branch and applies on request |
| `alacritty` | Terminal emulator |
| `firefox` | Firefox, with addons from NUR |
| `bat` | Syntax-highlighted `cat` |
| `eza` | Modern `ls` |
| `zoxide` | Smart directory jumping |
| `direnv` | Per-directory development environments |

### `stewos.desktop`

The largest module, and the one worth knowing the options of:

| Option | Description |
|--------|-------------|
| `monitors` | Monitor list: description, resolution, position, scale (Linux) |
| `keyboards` | Per-keyboard overrides, keyed by device name (Linux) |
| `bindings` | Keybindings, keyed by name; see below |
| `modifier` | Global modifier prefix for keybindings (default `SUPER`) |
| `terminal` | Terminal package (default Alacritty) |
| `wallpaper` | Path to a wallpaper image |
| `fonts.ui` / `fonts.monospace` | Interface and monospace fonts, shared by every toolkit |
| `startLocked` | Bring the session up locked (Linux) |
| `capsLockEscape` | Send Escape when Caps Lock is pressed |
| `swapCommandAlt` | Swap left Command and left Alt (macOS) |

None of these name a compositor. Hyprland runs the desktop on Linux and
Aerospace on macOS, but that lives in `modules/home-manager/desktop/linux/` and
`.../darwin/`; a host describes what it wants and the backend for the platform
it is built for works out how to ask for it.

Bindings are keyed by a name you choose, and name a `key`, the `modifiers` held
with it, and either a neutral `action` or a `command` to run:

```nix
stewos.desktop.bindings = {
  # Retarget a binding StewOS provides
  launcher.key = "space";

  # Or stop binding it
  power-menu.enable = false;

  # Or add one of your own
  notes = {
    key = "n";
    modifiers = [ "shift" ];
    command.package = pkgs.obsidian;
  };
};
```

Each backend owns a table saying what every neutral key name and action means
to it, and asserts on anything it cannot render — so a typo, a duplicated key
combination, or an action the platform cannot perform fails at build time
rather than at compositor startup. Aerospace does not implement `lock-session`
or the media keys, for instance; restrict such a binding with
`platforms = [ "linux" ]`.

## Packages

Custom packages live in their own scope, reachable as `pkgs.stewos.<name>` with
the overlay applied, and buildable as `nix build .#<name>`.

| Package | Description |
|---------|-------------|
| `gh-actions-language-server` | LSP for GitHub Actions workflow files |
| `lucas-chess` | Lucas Chess R2 |
| `shortcut-cli` | Command line client for shortcut.com |
| `wl-gen-uuid` | Generate a UUID onto the Wayland clipboard |
| `rofi-theme` | The StewOS Rofi theme |
| `rofi-hyprpower` | Rofi script mode for session power actions |
| `rofi-libvirt` | Rofi script mode for starting and connecting to VMs |

The scope also holds the `mkRofiConfig` and `mkRofiTheme` builders. They are
functions rather than derivations, so they are not part of the `packages`
output.

## Using StewOS From Another Flake

Start from the template:

```bash
nix flake new -t github:calebstewart/stewos#nixos-single ./my-config
```

To wire it up by hand, note that StewOS exports module trees rather than builder
functions. The modules reference StewOS's own inputs from inside `imports`,
where only `specialArgs` are available, so those inputs have to be handed back
in:

```nix
nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
  specialArgs = { inputs = stewos.lib.moduleInputs; };
  modules = [ stewos.nixosModules.default ./configuration.nix ];
};
```

This means `inputs` inside a StewOS module always refers to StewOS's inputs.
Pass your own under a different name.

The modules also expect two overlays on the `pkgs` you give them: StewOS's
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

## Conventions

- Privilege escalation is `doas`, not `sudo`
- Git forces SSH URLs for GitHub and signs commits with an SSH key
- `system.stateVersion` is per-machine; Home-Manager's is shared
- Platform differences go through `lib.mkIf pkgs.stdenv.isLinux`
- Overridable values use `lib.mkDefault`
- Formatting is `nix fmt` (nixfmt-tree)
