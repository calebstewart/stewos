{
  description = "Personal NixOS / Home-Manager Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    nix-colors.url = "github:misterio77/nix-colors";

    stewos = {
      url = "github:calebstewart/stewos";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-colors.follows = "nix-colors";
    };
  };

  outputs =
    { stewos, ... }@inputs:
    let
      hostname = "my-hostname";
      system = "x86_64-linux";

      user = {
        username = "yourname";
        fullname = "Your Name";
        email = "your.name@server.tld";

        # This is optional, but is used by some applications. Most noteably
        # is git, which will be configured to modify your default name and
        # email if the CWD is under `~/git/{name-of-alias}`. In this case,
        # all repos under `~/git/work`. Along with the email, you can
        # also override `.fullname` to conditionally set your full name.
        #
        # The name 'work' here is arbitrary and could be anything like
        # "foo" or "google" or the name of the business for which you work.
        aliases.work.email = "your.name@yourjob.tld";
      };
    in
    {
      nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
        inherit hostname system user;

        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };

      homeConfigurations."${user.username}@${hostname}" = stewos.lib.mkHomeManagerConfig {
        inherit system user;

        homeDirectory = "/home/${user.username}";

        modules = [
          # We pass `inputs` here so that we have access to nix-colors
          (import ./home.nix inputs)
        ];
      };
    };
}
