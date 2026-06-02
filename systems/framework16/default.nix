{
  hostname,
  stewos,
  ...
}@inputs:
let
  system = "x86_64-linux";

  user = {
    username = "caleb";
    fullname = "Caleb Stewart";
    email = "caleb.stewart94@gmail.com";
  };
in
{
  nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
    inherit hostname system user;

    modules = [
      ./hardware-configuration.nix
      (import ./configuration.nix inputs)
    ];
  };

  homeConfigurations."caleb@${hostname}" = stewos.lib.mkHomeManagerConfig {
    inherit system user;

    homeDirectory = "/home/caleb";
    modules = [ (import ./home.nix inputs) ];
  };
}
