# User Definitions
This directory contains all users defined for StewOS. The individual users
are defined by two components: `system.nix` and `home.nix`. The former is
required to create the users in NixOS while the latter is optional, but
used for defining the home manager configuration.

## `USER/system.nix`
This file is a NixOS module, and should create the desired user, and configure
any required system-level packages or settings (e.g. NixOS trusted users).

If the user uses `home-manager` (and has a `home.nix`), you can configure
the `home-manager.users.${username}` field with
`stew.mkHomeManagerUser "username"`. This will load the `home.nix` file for
your user. Alternatively, just creating `home.nix` will also expose the
home manager configuration as a flake output for use with the
`home-manager` command line tool directly.

## `USER/home.nix`
This file is a Home Manager configuration for the given user. If present,
the root flake will expose a `homeConfigurations.${username}` field which
points to this home configuration.
