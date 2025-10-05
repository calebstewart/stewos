{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    services.hypridle = {
      enable = true;

      settings = let
        hyprctl = lib.getExe config.wayland.windowManager.hyprland.package;
        loginctl = lib.getExe' pkgs.systemd "loginctl";
        brightnessctl = lib.getExe pkgs.brightnessctl;
        stew-shell = lib.getExe pkgs.stew-shell;
      in {
        general = {
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
          before_sleep_cmd = "${loginctl} lock-session";
          lock_cmd = "${stew-shell} lock";
        };

        listener = [
          {
            timeout = cfg.idle.dimSeconds;
            on-timeout = "${brightnessctl} --save set 10";
            on-resume = "${brightnessctl} --restore";
          }
          {
            timeout = cfg.idle.lockSeconds;
            on-timeout = "${loginctl} lock-session";
          }
          {
            timeout = cfg.idle.sleepSeconds;
            on-timeout = "${hyprctl} dispatch dpms off";
            on-resume = "${hyprctl} dispatch dpms on";
          }
        ];
      };
    };
  };
}
