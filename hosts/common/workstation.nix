# Policy shared by the Framework machines: Secure Boot via lanzaboote, a silent
# boot, the StewOS modules they both run, and sleep settings that permit
# hibernation.
#
# This is host policy rather than a reusable module, which is why it lives under
# hosts/ and is imported explicitly instead of being hidden behind an option.
# Anything that is genuinely per-machine -- hardware modules, stateVersion,
# services only one of them runs -- stays in that machine's configuration.nix.
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
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

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

    kernelPackages = pkgs.linuxPackages_latest;

    # Silent boot stuff. Machines append their own parameters to this list.
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

  # This prevents hibernation
  security.protectKernelImage = false;

  # Setup systemd sleep configuration
  systemd.sleep.settings.Sleep = {
    AllowHybridSleep = true;
    AllowSuspend = true;
    AllowHibernate = true;
  };

  # sbctl manages the Secure Boot keys under /var/lib/sbctl
  environment.systemPackages = [ pkgs.sbctl ];

  # Enable power management so we can see the battery
  services.upower.enable = true;
}
