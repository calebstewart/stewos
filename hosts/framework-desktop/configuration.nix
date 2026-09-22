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

  # DP-1 loses HPD across an s2idle resume. amdgpu comes back believing nothing
  # is plugged into that port, and because no hotplug interrupt ever arrives it
  # never revisits the question -- the resume is completely silent in the
  # journal. The sink is healthy the entire time: forcing the detect over
  # debugfs brings the link straight up, EDID and link training included. So
  # this is HPD sense alone, not the monitor, and Windows on this same hardware
  # is unaffected. HDMI-A-1 carries no equivalent link state and never fails.
  #
  # "trigger_hotplug" is the forced path and the reason this works.
  # "echo detect > .../status" is NOT a substitute: that route consults HPD, so
  # it agrees the port is empty and reports disconnected. Power-cycling the
  # monitor by hand works for the same reason this does -- it manufactures an
  # HPD edge -- which is why the monitor looked guilty for a long time.
  #
  # The poll runs first so a healthy resume is left completely alone; only a
  # connector still dark after ~10s is forced. Both numbers are globbed because
  # neither is stable: the DRM card index and the dri debugfs index are assigned
  # at probe.
  systemd.services.dp-resume-hotplug = {
    description = "Force a DRM hotplug on DP-1, which loses HPD across resume";
    after = [ "post-resume.target" ];
    wantedBy = [ "post-resume.target" ];
    path = [ pkgs.coreutils ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dp-resume-hotplug" ''
        for connector in DP-1; do
          for status in /sys/class/drm/card*-$connector/status; do
            [ -e "$status" ] || continue

            attempts=5
            state=""

            while [ "$attempts" -gt 0 ]; do
              read -r state < "$status"

              if [ "$state" = connected ]; then
                break
              fi

              attempts=$((attempts - 1))

              if [ "$attempts" -gt 0 ]; then
                sleep 2
              fi
            done

            if [ "$state" = connected ]; then
              continue
            fi

            for trigger in /sys/kernel/debug/dri/*/$connector/trigger_hotplug; do
              [ -e "$trigger" ] || continue
              echo "$connector still disconnected after resume; forcing hotplug"
              echo 1 > "$trigger"
            done
          done
        done
      '';
    };
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
