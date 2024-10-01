# User Definitions
This directory contains the definitions for users agnostic of the system
on which they are installed. A system can enable individual users with
the `modules.users.{username}.enable` configuration.

For each user, `system.nix` is a NixOS module which is responsible for
creating the user, and setting any required system-level settings for
the user. The `home.nix` file is a home-manager module for configuring
the user. `home.nix` is technically optional for any given user, but
if present it will be exposed as a flake output under the name
`homeConfigurations.${username}`.
