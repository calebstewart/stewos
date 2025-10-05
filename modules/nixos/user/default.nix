{...}:
{lib, config, pkgs, ...}:
let
  cfg = config.stewos.user;
in {
  options.stewos.user = {
    username = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = "Name of the default StewOS user";
    };

    fullname = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Full name of the default StewOS user";
    };

    groups = lib.mkOption {
      description = "List of groups that hsould be applied to the default user";
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf (cfg.username != null) {
    # Setup extra user groups
    users.users.${cfg.username} = {
      description = cfg.fullname;
      group = cfg.username;
      extraGroups = ["wheel" "dialout"] ++ cfg.groups;
      shell = pkgs.zsh;
      createHome = true;
      isNormalUser = true;
      initialPassword = "password";
    };

    # Create the user group
    users.groups.${cfg.username} = {};

    # Enable our default shell
    programs.zsh.enable = true;

    # Allow the user to manage nix
    nix.settings.trusted-users = [cfg.username];

    # Set the default location for the flake repository
    programs.nh.flake = lib.mkDefault "${config.users.users.${cfg.username}.home}/git/nix";

    # Allow the default user to use 'doas' for privesc
    security.doas.extraRules = [{
      users = [cfg.username];
      keepEnv = true;
      persist = true;
    }];

    # Allow SSH inbound
    services.openssh.settings.AllowUsers = [cfg.username];
  };
}
