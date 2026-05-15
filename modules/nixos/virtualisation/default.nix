{ vfio-hooks, ... }:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.virtualisation;
in
{
  options.stewos.virtualisation.enable = lib.mkEnableOption "virtualisation";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      virt-manager
    ];

    virtualisation.libvirtd = {
      enable = true;
      nss.enable = true;
      nss.enableGuest = true;

      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    # Install vfio-hooks
    environment.etc."libvirt/hooks/qemu" = {
      source = "${vfio-hooks}/libvirt_hooks/qemu";
    };

    # Allow communication from VM to host over common ephemeral ports
    # This is normally things like updog for transferring files.
    networking.firewall.interfaces."virbr0" = {
      allowedTCPPortRanges = [
        {
          from = 8000;
          to = 10000;
        }
      ];

      allowedUDPPorts = [
        53
        67
      ];
    };

    networking.nat = {
      enable = true;
      internalInterfaces = [ "virbr0" ];
    };
  };
}
