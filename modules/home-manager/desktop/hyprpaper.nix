{lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    # Configure Wallpaper Manager
    services.hyprpaper = {
      enable = true;

      settings = {
        ipc = "off";
        splash = false;
        splash_offset = 2.0;

        preload = ["${cfg.wallpaper}"];
        wallpaper = [",${cfg.wallpaper}"];
      };
    };
  };
}
