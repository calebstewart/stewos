{
  hostname,
  stewos,
  home-manager,
  ...
}@inputs:
let
  system = "aarch64-darwin";

  user = {
    username = "caleb.stewart";
    fullname = "Caleb Stewart";
    email = "caleb.stewart94@gmail.com";
    aliases.personal.email = "caleb.stewart94@gmail.com";
  };
in
{
  darwinConfigurations.${hostname} = stewos.lib.mkNixDarwinSystem {
    inherit hostname system;

    modules = [
      ./configuration.nix
    ];
  };

  homeConfigurations."caleb.stewart@${hostname}" = stewos.lib.mkHomeManagerConfig {
    inherit system user;

    isDarwin = true;
    homeDirectory = "/Users/${user.username}";
    modules = [ (import ./home.nix inputs) ];
  };
}
