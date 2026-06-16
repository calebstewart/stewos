{ config, pkgs, ... }:
{
  system.stateVersion = 6;

  # Host-specific nix-darwin configuration
  system.primaryUser = "caleb.stewart";
  system.startup.chime = false;

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    # This fucks with aerospace
    spaces.spans-displays = false;

    # I hate this "feature"
    WindowManager.EnableStandardClickToShowDesktop = false;
  };

  homebrew = {
    enable = true;

    brews = [ "ruby-install" ];
    casks = [ "karabiner-elements" ];
  };

  programs.nh.flake = "${config.users.users."caleb.stewart".home}/git/personal/stewos";
  users.users."caleb.stewart".home = "/Users/caleb.stewart";

  environment.systemPackages = [
    pkgs.raycast
  ];
}
