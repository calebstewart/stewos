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
    inputs.nur.modules.nixos.default
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
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
      "ttm.pages_limit=29360128"
      "ttm.page_pool_size=29360128"
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

  networking = {
    wireguard.enable = true;
    nftables.enable = true;

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = [ 443 ];
      allowedUDPPorts = [
        1194
        config.services.tailscale.port
      ];
    };
  };

  # Install extra packages
  environment.systemPackages = [ pkgs.sbctl ];

  time.timeZone = "America/Chicago";

  services = {
    # Enable printing
    printing = {
      enable = true;

      drivers = with pkgs; [
        cups-filters
        cups-browsed
      ];
    };

    # Enable network printer discovery
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Enable firmware upgrades
    fwupd.enable = true;

    # Enable power management daemon
    upower.enable = true;

    ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
    };

    nordvpn.enable = true;

    tailscale.enable = true;
  };

  # Force nftables usage for tailscale
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  hardware.logitech.wireless = {
    enable = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # Speed up boot w/ a VPN
  systemd.network.wait-online.enable = true;
  boot.initrd.systemd.network.wait-online.enable = false;
}
