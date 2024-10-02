{stewos, ...}:
let
  hostname = "ryzen";
  system = "x86_64-linux";
in rec {
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
    inherit system hostname;
  };

  apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp nixosConfigurations.${hostname};
}
