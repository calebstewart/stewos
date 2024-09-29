{pkgs, lib, config, stew, ...}:
let
  username = "caleb";
  fullname = "Caleb Stewart";

  cfg = config.modules.users.${username};
in {
  options.modules.users.${username} = {
    enable = lib.mkEnableOption username;
    enableHomeManager = lib.mkEnableOption "home-manager";
  };

  config = lib.mkIf cfg.enable {
    # Create the user
    users.users.${username} = {
      description = fullname;
      isNormalUser = true;
      createHome = true;
      shell = pkgs.zsh;
      extraGroups = config.modules.users.admin_groups ++ config.modules.users.base_groups;
      initialPassword = "password";
    };

    # Enable NixOS-managed Home Manager
    home-manager.users.${username} = lib.mkIf cfg.enableHomeManager (import ./home.nix);

    # Allow nix management as caleb
    nix.settings.trusted-users = [username];

    # Set the flake path to the git repo for this user
    programs.nh.flake = "/home/${username}/git/nix";

    # Enable zsh for our shell
    programs.zsh.enable = true;
  };
}
