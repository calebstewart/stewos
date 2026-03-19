{ config, pkgs, ... }:
{
  system.stateVersion = 6;

  # Host-specific nix-darwin configuration
  system.primaryUser = "caleb";
  services.karabiner-elements.enable = true;
  system.startup.chime = false;

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    # This fucks with aerospace
    spaces.spans-displays = false;

    # I hate this "feature"
    WindowManager.EnableStandardClickToShowDesktop = false;
  };

  # Maintain legacy UIDs
  ids.gids.nixbld = 30000;

  homebrew = {
    enable = true;

    taps = [ "ubuntu/microk8s" ];
    brews = [
      "ruby-install"
      "ubuntu/microk8s/microk8s"
    ];
    casks = [ ];
  };

  programs.nh.flake = "${config.users.users.caleb.home}/git/stewos";
  users.users.caleb.home = "/Users/caleb";

  environment.systemPackages = [ pkgs.raycast ];
}
