{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    # Automatically Start the Gnome Polkit Authentication Agent
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      Unit.Description = "Polkit Gnome Authentication Agent";

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };

      Install.WantedBy = ["graphical-session.target"];
    };
  };
}

