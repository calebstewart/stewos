{
  nixos-hardware,
  lanzaboote,
  nixpkgs-unstable,
  nur,
  ...
}@inputs:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  user = config.stewos.user;
  pkgs-unstable = nixpkgs-unstable.legacyPackages.${pkgs.system};
in
{
  imports = [
    nur.modules.nixos.default
    nur.legacyPackages.x86_64-linux.repos.wingej0.modules.nordvpn
    nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    lanzaboote.nixosModules.lanzaboote
  ];

  # nixpkgs.overlays = [
  #   (final: prev: {
  #     nordvpn = prev.nur.repos.wingej0.nordvpn;
  #   })
  # ];

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
  systemd.sleep.extraConfig = ''
    AllowHybridSleep=yes
    AllowSuspend=yes
    AllowHibernate=yes
  '';

  networking = {
    wireguard.enable = true;

    firewall = {
      checkReversePath = false;
      allowedTCPPorts = [ 443 ];
      allowedUDPPorts = [ 1194 ];
    };
  };

  # Install extra packages
  environment.systemPackages = [ pkgs.sbctl ];

  time.timeZone = "America/Chicago";

  # Enable printing
  services.printing = {
    enable = true;

    drivers = with pkgs; [
      cups-filters
      cups-browsed
    ];
  };

  # Enable network printer discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Enable firmware upgrades
  services.fwupd.enable = true;

  # Enable power management daemon
  services.upower.enable = true;

  hardware.logitech.wireless = {
    enable = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama-rocm;
  };

  services.nordvpn.enable = true;
}
