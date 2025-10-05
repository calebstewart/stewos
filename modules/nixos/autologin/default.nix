{...}:
{lib, config, ...}:
let
  cfg = config.stewos.autologin;
in {
  options.stewos.autologin = {
    enable = lib.mkEnableOption "autologin";
    
    username = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = "Name of the user to automatically login";
    };

    command = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = "Command to execute when automatically logged in";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.stewos.greeter.enable;
        message = "one of greeter and autologin modules can be enabled at a time";
      }
      {
        assertion = cfg.username != null;
        message = "a username is required for autologin module";
      }
      {
        assertion = cfg.command != null;
        message = "a command is required for autologin module";
      }
    ];

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
    services.greetd = {
      enable = true;

      settings.initial_session = {
        inherit (cfg) command;
        user = cfg.username;
      };
    };

    # Enable programs which provide sessions
    programs.hyprland.enable = true;
  };
}
