{lib, config, pkgs, inputs}:
let
  cfg = config.stewos.virtualisation;
in {
  options.stewos.virtualisation.enabe = lib.mkEnableOption "virtualisation";

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;

      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;

        ovmf = {
          enable = true;
          packages = with pkgs; [
            OVMFFull.fd
          ];
        };
      };
    };

    # Install vfio-hooks
    environment.etc."libvirt/hooks/qemu" = {
      source = "${inputs.vfio-hooks}/libvirt_hooks/qemu";
    };

    # Allow communication from VM to host over common ephemeral ports
    # This is normally things like updog for transferring files.
    networking.firewall.interfaces."virbr0".allowedTCPPortRanges = [
      { from = 8000; to = 10000; }
    ];
  };
}
