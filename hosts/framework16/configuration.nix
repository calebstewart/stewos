{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  user = config.stewos.user;
in
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-16-7040-amd
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # The NixOS release this machine was first installed from. Per-machine on
  # purpose: it must not follow whatever the shared modules were written for.
  # DO NOT CHANGE.
  system.stateVersion = "24.05";

  stewos = {
    audio.enable = true;
    desktop-services.enable = true;
    greeter.enable = false;
    zsa.enable = false;
    virtualisation.enable = true;
    sshd.enable = true;
    looking-glass.enable = false;

    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatibility = true;
    };

    autologin = {
      enable = true;
      username = user.username;
      command = "${config.users.users.${user.username}.home}/.wayland-session";
    };
  };

  boot = {
    # Disable in favor of Lanzaboote for Secure Boot
    loader.systemd-boot.enable = lib.mkForce false;
    loader.systemd-boot.editor = false;
    loader.timeout = 0;

    # Enable Lanzaboote for Secure Boot support
    lanzaboote.enable = true;
    lanzaboote.pkiBundle = "/var/lib/sbctl";

    # Some tweaks for this specific hardware
    kernelPackages = pkgs.linuxPackages_latest;

    # Silent boot stuff
    kernelParams = [
      "quiet"
      "splash"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
      "udev.log_level=3"
    ];

    # Disable logging
    consoleLogLevel = 0;
    initrd.verbose = false;
  };

  # Set the system hostname
  networking.hostName = "framework16";

  # This prevents hibernation
  security.protectKernelImage = false;

  # Setup systemd sleep configuration
  systemd.sleep.settings.Sleep = {
    AllowHybridSleep = true;
    AllowSuspend = true;
    AllowHibernate = true;
  };

  # Install extra packages
  environment.systemPackages = [ pkgs.sbctl ];

  # Enable power management so we can see the battery
  services.upower.enable = true;
}
