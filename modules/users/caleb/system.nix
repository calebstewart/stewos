{pkgs, lib, config, ...}:
let
  username = "caleb";
  fullname = "Caleb Stewart";

  cfg = config.stewos.users.${username};
in {
  options.stewos.users.${username} = {
    enable = lib.mkEnableOption username;
  };

  config = lib.mkIf cfg.enable {
    # Create the user
    users.users.${username} = {
      description = fullname;
      isNormalUser = true;
      createHome = true;
      shell = pkgs.zsh;
      extraGroups = config.stewos.users.admin_groups ++ config.stewos.users.base_groups;
      initialPassword = "password";
    };

    # Enable NixOS-managed Home Manager
    home-manager.users.${username} = import ./home.nix;

    # Allow nix management as caleb
    nix.settings.trusted-users = [username];

    # Set the flake path to the git repo for this user
    programs.nh.flake = "/home/${username}/git/nix";

    # Enable zsh for our shell
    programs.zsh.enable = true;
  };
}
