{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    systemd.user.services.stew-shell = {
      Unit = {
        Description = "Desktop Shell User Interface";
      };

      Service = {
        Type = "simple";
        ExecStart = lib.getExe pkgs.stew-shell;
        Restart = "on-failure";
      };

      Install.WantedBy = ["hyprland-session.target"];
    };
  };
}
