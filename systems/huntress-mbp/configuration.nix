{...}:
{...}: {
  # Host-specific nix-darwin configuration
  system.primaryUser = "caleb";
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  system.keyboard.swapLeftCommandAndLeftAlt = true;
  # system.keyboard.swapLeftCtrlAndFn = true;
  system.startup.chime = false;

  homebrew = {
    enable = true;

    taps = ["ubuntu/microk8s"];
    brews = ["ruby-install" "ubuntu/microk8s/microk8s"];
    casks = [];
  };
}
