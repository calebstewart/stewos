{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    # The Hyprland polkit authentication agent, which draws the
    # privilege-escalation prompts (run0, pkexec, ...). pkgs.stewos wraps the
    # upstream flake package (nixpkgs still ships the pre-hyprtoolkit Qt
    # build) with a rendering fix; see pkgs/hyprpolkitagent.
    services.hyprpolkitagent = {
      enable = true;
      package = pkgs.stewos.hyprpolkitagent;
    };

    systemd.user.services.hyprpolkitagent = {
      # The home-manager unit has no Restart policy; add one.
      Service = {
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };
}
