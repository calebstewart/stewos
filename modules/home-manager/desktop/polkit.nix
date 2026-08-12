{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    # The Hyprland polkit authentication agent, which draws the
    # privilege-escalation prompts (run0, pkexec, ...). The package comes from
    # the upstream flake because nixpkgs still ships the pre-hyprtoolkit Qt
    # build (see the input comment in flake.nix).
    services.hyprpolkitagent = {
      enable = true;
      package = inputs.hyprpolkitagent.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    # The home-manager unit has no Restart policy; add one.
    systemd.user.services.hyprpolkitagent.Service = {
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
