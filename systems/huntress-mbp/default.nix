{
  hostname,
  stewos,
  home-manager,
  ...
}@inputs:
let
  system = "aarch64-darwin";
in
{
  darwinConfigurations.${hostname} = stewos.lib.mkNixDarwinSystem {
    inherit hostname;

    system = "aarch64-darwin";
    modules = [
      (import ./configuration.nix inputs)
    ];
  };

  homeConfigurations."caleb@${hostname}" = stewos.lib.mkHomeManagerConfig {
    inherit system;

    username = "caleb";
    homeDirectory = "/Users/caleb";
    modules = [ (import ./home.nix inputs) ];
  };
}
