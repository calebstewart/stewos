{lib, config, user, ...}:
let
  cfg = config.stewos.security;
in {
  options.stewos.security = {
    administrators = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of users allowed to use the doas command to run commands as root";
    };
  };

  config = {
    # We do not use sudo
    security.sudo.enable = false;

    # Configure doas to allow the administrators
    security.doas.enable = true;

    # Allow hyprlock to unlock the system
    security.pam.services.hyprlock = {};
  };
}
