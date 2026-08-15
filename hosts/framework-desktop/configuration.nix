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

  # Hibernation is off on this machine, and it is not a preference -- an S4
  # attempt here bricks the GPU until the PSU is unplugged. 128 GiB of RAM
  # against a 14.9 GiB swap partition means the image does not fit, and amdgpu
  # does not survive the aborted hibernate that follows. See "The desktop wakes
  # up with a dead GPU" in CLAUDE.md for the whole chain.
  #
  # Belt and braces. protectKernelImage puts `nohibernate` on the kernel
  # command line, so S4 is impossible no matter what asks for it; the sleep
  # settings stop systemd trying in the first place, so a request fails loudly
  # instead of getting halfway. Plain suspend (s2idle) is unaffected by either.
  # The kexec that protectKernelImage also disables is unused here.
  security.protectKernelImage = true;

  systemd.sleep.settings.Sleep = {
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
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
