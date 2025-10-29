{ config, ... }:
{
  system.stateVersion = 6;

  # Host-specific nix-darwin configuration
  system.primaryUser = "caleb";
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  system.keyboard.swapLeftCommandAndLeftAlt = true;
  # system.keyboard.swapLeftCtrlAndFn = true;
  system.startup.chime = false;

  # This fucks with aerospace
  system.defaults.spaces.spans-displays = false;

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
}
