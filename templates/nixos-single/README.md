# StewOS - NixOS Single-User System Flake

This flake template provides a single NixOS system configuration output
and a Home Manager configuration output. Both outputs are intended for
the same system and automatically use StewOS.

## Setup

Before this flake will work, you must first initialize a git repository
and add the files to `git`. You must also copy `hardware-configuration.nix`
to this directory and add it to `git` as well. This file should have been
generated for you when you installed/setup your base NixOS system.

```bash
git init
cp /etc/nixos/hardware-configuration.nix .
git add .
```

Then edit the following:

- `flake.nix` -- your hostname, user name, full name, and email address.
  This is used to configure your user information and certain
  applications such as `git`.
- `configuration.nix` -- `system.stateVersion` should be the NixOS
  release you installed from, and stays fixed after that. Enable the
  StewOS system modules you want under `stewos.*`.
- `home.nix` -- enable the StewOS Home Manager modules you want.

StewOS sets up `nh` for managing your NixOS and Home Manager configurations
and expects that your system configuration flake is stored in `~/git/stewos`.

## How this flake is wired

StewOS exports module trees rather than builder functions, so `flake.nix`
constructs the configurations itself. Two details are worth knowing:

**`inputs` refers to StewOS's inputs, not yours.** StewOS modules
reference their own inputs (stylix, nixvim, nix-colors, ...) from inside
`imports`, where only `specialArgs` are available, so `flake.nix` passes
`inputs = stewos.lib.moduleInputs`. That is why `home.nix` can write
`inputs.nix-colors.colorSchemes.catppuccin-mocha` without declaring
`nix-colors` as an input of your own. If you want your own flake inputs
available inside your configuration files, pass them through
`specialArgs` under a different name.

**Two overlays are applied.** `stewos.overlays.default` puts the custom
StewOS packages in their own scope, reachable as `pkgs.stewos.<name>` --
for example `pkgs.stewos.wl-gen-uuid`. NUR is applied alongside it
because the `stewos.firefox` module pulls browser addons from
`pkgs.nur`. Regular nixpkgs packages are unaffected by either.

## Building

```bash
# First time, before nh is available
sudo nixos-rebuild switch --flake .#your-hostname

# Afterwards
nh os switch .
nh home switch .
```

For more information, please visit the StewOS GitHub: https://github.com/calebstewart/stewos
