{stewos, ...}:
let
  hostname = "framework16";
  system = "x86_64-linux";
in rec {
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
    inherit system hostname;
  };

  apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp nixosConfigurations.${hostname};
}
