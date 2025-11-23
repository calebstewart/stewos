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
      username = "yourname";
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
        inherit hostname system;

        modules = [
          ./hardware-configuration.nix

          # We pass `inputs` here so that we have access to nix-colors
          (import ./configuration.nix inputs)
        ];
      };

      homeConfigurations."${username}@${hostname}" = stewos.lib.mkHomeManagerConfig {
        inherit system username;

        homeDirectory = "/home/${username}";
        modules = [ ./home.nix ];
      };
    };
}
