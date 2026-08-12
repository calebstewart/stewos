{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../common/workstation.nix
    inputs.nur.modules.nixos.default
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
  ];

  # The NixOS release this machine was first installed from. Per-machine on
  # purpose: it must not follow whatever the shared modules were written for.
  # DO NOT CHANGE.
  system.stateVersion = "24.05";

  # Appended to the silent-boot parameters set by the workstation profile.
  boot.kernelParams = [
    "ttm.pages_limit=29360128"
    "ttm.page_pool_size=29360128"
  ];

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
