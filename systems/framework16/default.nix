{
  hostname,
  stewos,
  home-manager,
  ...
}@inputs:
let
  system = "x86_64-linux";

  config = stewos.lib.mkNixOSSystem {
    inherit hostname system;

    modules = [
      home-manager.nixosModules.default
      ./hardware-configuration.nix
      (import ./configuration.nix inputs)
    ];
  };
in
{
  nixosConfigurations.${hostname} = config;
  apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp hostname config;
}
