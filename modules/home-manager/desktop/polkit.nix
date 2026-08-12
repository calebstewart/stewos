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
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    # The Hyprland polkit authentication agent, which draws the
    # privilege-escalation prompts (run0, pkexec, ...).
    services.hyprpolkitagent.enable = true;

    # The home-manager unit has no Restart policy; add one.
    systemd.user.services.hyprpolkitagent.Service = {
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
