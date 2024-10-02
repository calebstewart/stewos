{
  description = "Personal NixOS / Home-Manager / Nix-Darwin Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    nix-colors.url = "github:misterio77/nix-colors";
    nur.url = "github:nix-community/NUR";
    nix-std.url = "github:chessai/nix-std";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vfio-hooks = {
      url = "github:PassthroughPOST/VFIO-Tools";
      flake = false;
    };
  };

  outputs = {self, ...}@inputs:
  let
    # Base outputs which don't need any fancieness
    baseOutputs = {
      lib = import ./lib/default.nix {
        inherit inputs;
        stewos = self;
      };

      nixosModules = import ./modules/nixos/individual.nix {
        inherit inputs;
        stewos = self;
      };

      homeModules = import ./modules/home-manager/individual.nix {
        inherit inputs;
        stewos = self;
      };

      darwinModules = import ./modules/nix-darwin/individual.nix {
        inherit inputs;
        stewos = self;
      };
    };

    # Packages which must use the flake-utils helper
    packageOutputs = inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages = import ./packages {
        inherit inputs;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        stewos = self;
      };
    });

    # System outputs which may also provide overlapping output keys, and must
    # be recursively merged with the above two attrsets.
    systemOutputs = import ./systems {
      inherit inputs;
      stewos = self;
    };
  in inputs.nixpkgs.lib.attrsets.recursiveUpdate (baseOutputs // packageOutputs) systemOutputs;
}
