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
    # Automatically start the Hyprland polkit authentication agent, which
    # draws the privilege-escalation prompts (run0, pkexec, ...).
    systemd.user.services.hyprpolkitagent = {
      Unit.Description = "Hyprland Polkit Authentication Agent";

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
