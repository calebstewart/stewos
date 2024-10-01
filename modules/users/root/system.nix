{pkgs, lib, config, stew, ...}:
let
  username = "root";
  fullname = "System Administrator";

  cfg = config.stewos.users.${username};
in {
  options.stewos.users.${username} = {
    enable = lib.mkEnableOption username;
    enableHomeManager = lib.mkEnableOption "home-manager";
  };

  config = lib.mkIf cfg.enable {
    # Create the user
    users.users.${username} = {
      description = fullname;
      shell = pkgs.zsh;
    };

    # Allow nix management as caleb
    nix.settings.trusted-users = [username];

    # Required to set shell to zsh
    programs.zsh.enable = true;
  };
}
