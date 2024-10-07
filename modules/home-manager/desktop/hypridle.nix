{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    services.hypridle = {
      enable = true;

      settings = let
        hyprctl = "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
        loginctl = "${pkgs.systemd}/bin/loginctl";
        hyprlock = "${pkgs.hyprlock}/bin/hyprlock";
        brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
        pidof = "${pkgs.procps}/bin/pidof";
      in {
        general = {
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
          before_sleep_cmd = "${loginctl} lock-session";
          lock_cmd = "${pidof} hyprlock || ${hyprlock}";
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
