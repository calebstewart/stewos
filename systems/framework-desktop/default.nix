{
  hostname,
  stewos,
  ...
}@inputs:
let
  system = "x86_64-linux";
in
{
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
    inherit hostname system;

    modules = [
      ./hardware-configuration.nix
      (import ./configuration.nix inputs)
    ];
  };

  homeConfigurations."caleb@${hostname}" = stewos.lib.mkHomeManagerConfig {
    inherit system;

    username = "caleb";
    homeDirectory = "/home/caleb";
    modules = [ (import ./home.nix inputs) ];
  };
}
