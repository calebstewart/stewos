{ hostname, stewos, ... }:
let
  system = "x86_64-linux";

  config = stewos.lib.mkNixOSSystem {
    inherit hostname system;

    modules = [
      ./hardware-configuration.nix
      ./configuration.nix
    ];
  };
in
{
  nixosConfigurations.${hostname} = config;
  apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp hostname config;
}
