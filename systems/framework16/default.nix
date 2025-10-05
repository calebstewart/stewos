{stewos, ...}:
let
  hostname = "framework16";
  system = "x86_64-linux";
in rec {
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
    inherit system;

    modules = [
      ./hardware-configuration.nix
      ./configuration.nix
    ];
  };

  apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp nixosConfigurations.${hostname};
}
