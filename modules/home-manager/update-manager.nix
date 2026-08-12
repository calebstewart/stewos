{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.update-manager;
in
{
  options.stewos.update-manager = {
    enable = lib.mkEnableOption "the StewOS update-manager tray daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.stewos.update-manager;
      description = "The update-manager package to run.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/git/stewos";
      description = "Git checkout of the flake to update and merge back into.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "stewos-update";
      description = "Branch the update check builds on.";
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [ cfg.package ];

    systemd.user.services.stewos-update-manager = {
      Unit = {
        Description = "StewOS update-manager tray daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} --flake ${cfg.flakePath} --branch ${cfg.branch}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
