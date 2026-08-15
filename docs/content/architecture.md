# Architecture

The organising rule is that **nothing is discovered by scanning a directory**.
Adding a module means adding a line to that platform's `default.nix`; adding a
package means adding a line to `pkgs/default.nix`. Every import is greppable,
and the complete list of what exists is always a file you can read.

```
flake.nix          Inputs and every output, declared explicitly.
                   The only place flake inputs are captured.
overlays/          The StewOS overlay, which adds pkgs.stewos.*
pkgs/              Package definitions; plain callPackage derivations
lib/               Pure helpers: takes a nixpkgs lib, returns functions
modules/
  common/          Options shared by NixOS and Home-Manager
  nixos/           NixOS system modules
  home-manager/    Home-Manager user modules
  nix-darwin/      macOS system modules
hosts/             Machine-specific configuration only
templates/         Flake templates for new systems
```

## Modules

Modules are ordinary module files, imported by path. `inputs` arrives through
`specialArgs`, which `flake.nix` sets once:

```nix
{ inputs, lib, config, pkgs, ... }:
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

A module that needs several files gets a directory with a `default.nix`;
everything else is a single `{name}.nix`.

## Packages and the overlay

Packages under `pkgs/` never reference flake inputs. Anything that must come
from an input — a `flake = false` source tree, a colour scheme — is injected into
the scope by `overlays/default.nix` and resolved by argument name. That is what
keeps `pkgs/` buildable against a plain nixpkgs.

The modules expect two overlays on `pkgs`: `stewos.overlays.default` and NUR.

## Hosts

`hosts/{hostname}/` holds configuration only; the outputs are declared in
`flake.nix`, so the full set of configurations is visible in one file.
`hosts/common/workstation.nix` carries the policy the two Framework machines
share.

`system.stateVersion` deliberately stays per-host and must never move into
shared configuration. So does hibernation: the desktop cannot survive an aborted
S4 on its iGPU, and the laptop can.

## The desktop option surface names no compositor

`stewos.desktop` is deliberately platform-neutral. A binding is
`{ key, modifiers, useModifier, platforms, action | command }`, where `key` and
`action` are neutral names. Each backend — Hyprland on Linux, Aerospace on macOS
— owns three translation tables (modifiers, keys, actions) and asserts on
anything it does not implement.

Adding an action means adding it to `modules/home-manager/desktop/vocabulary.nix`
plus at least one backend's `actions` table. Hyprland and Rofi vocabulary stays
out of `options.nix`.

Each backend contributes its default keymap *through* `stewos.desktop.bindings`
with per-field `mkDefault`, which is what lets a host retarget or disable a
StewOS-provided binding by name.
