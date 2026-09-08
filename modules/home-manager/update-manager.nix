# The update-manager tray daemon comes from the nixos-update-manager flake
# (github:calebstewart/nixos-update-manager); this file only imports its
# home-manager module and fills in the values it leaves null or required with
# what StewOS already knows. It declares no options of its own: a host enables
# and customises the daemon at `services.nixos-update-manager.*`, and every
# default here is a mkDefault so it can be overridden in place.
#
# The upstream export already carries its own `_file`, so unlike embermug-tray
# it needs no wrapper for the option documentation to attribute it correctly.
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.nixos-update-manager;
  palette = config.colorScheme.palette;
in
{
  imports = [ inputs.nixos-update-manager.homeModules.default ];

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    services.nixos-update-manager = {
      flakePath = lib.mkDefault "${config.home.homeDirectory}/git/stewos";

      # Follows the desktop's terminal, which is the option a host already
      # sets. The editor is a PATH name on purpose, so it picks up the editor
      # the home profile installs (programs.neovim's `nvim`) instead of a
      # second one; Claude is a store path so it does not depend on the unit's
      # PATH, and comes from llm-agents rather than nixpkgs because nixpkgs
      # lags its releases.
      terminal = lib.mkDefault config.stewos.desktop.terminal;
      editor = lib.mkDefault "nvim";
      claudePackage =
        lib.mkDefault
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

      # The icon colours come out of the colour scheme so the tray follows a
      # scheme change the way theme.nix makes the rest of the desktop. The hues
      # are chosen so the temperature says whose turn it is: cool while the
      # daemon is working (0D checking, 0C building, 0E applying), warm when it
      # is the user's (0A decide, 09 fix the checkout, 08 something broke).
      # idle is base05 (the plain foreground) rather than one of the greys:
      # it is the state with nothing to say, and base03/base04 are surface
      # colours that all but disappear against a bar. The menu glyphs are
      # actions and take no meaning from their hue, so they share it.
      icons = lib.mapAttrs (_: slot: lib.mkDefault "#${palette.${slot}}") {
        idle = "base05";
        checking = "base0D";
        upToDate = "base0B";
        updatesAvailable = "base0A";
        applying = "base0E";
        building = "base0C";
        error = "base08";
        blocked = "base09";
        menu = "base05";
      };
    };
  };
}
