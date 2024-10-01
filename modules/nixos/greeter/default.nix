{pkgs, lib, config, ...}:
let
  cfg = config.stewos.greeter;
in {
  options.stewos.greeter = {
    enable = lib.mkEnableOption "greeter";
  };

  config = lib.mkIf cfg.enable {
    # Setup the regreet GTK4 greeter
    programs.regreet = {
      enable = true;

      settings = {
        GTK = {
          application_prefer_dark_theme = true;
        };

        commands = {
          reboot = ["systemctl" "reboot"];
          poweroff = ["systemctl" "poweroff"];
        };
      };
    };

    # Enable the greetd service
    services.greetd.enable = true;
  };
}
