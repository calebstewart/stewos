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
  };
}
