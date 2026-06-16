{ config, pkgs, ... }:
{
  system.stateVersion = 6;

  # Host-specific nix-darwin configuration
  system.primaryUser = "caleb.stewart";
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  system.keyboard.swapLeftCommandAndLeftAlt = true;
  # system.keyboard.swapLeftCtrlAndFn = true;
  system.startup.chime = false;

  # This fucks with aerospace
  system.defaults.spaces.spans-displays = false;

  homebrew = {
    enable = true;

    brews = [ "ruby-install" ];
    casks = [ "karabiner-elements" ];
  };

  programs.nh.flake = "${config.users.users."caleb.stewart".home}/git/personal/stewos";
  users.users."caleb.stewart".home = "/Users/caleb.stewart";

  environment.systemPackages = [ pkgs.raycast ];
}
