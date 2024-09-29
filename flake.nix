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

    # FIXME: Remove this when this PR is merged: https://github.com/viperML/nh/pull/92
    nh-extra-privesc.url = "github:henriquekirchheck/nh/b6513832b39521e60349f2b2ab83cc8d5d28194e";

    hyprsplit = {
      url = "github:shezdy/hyprsplit";
      flake = false;
    };

    vfio-hooks = {
      url = "github:PassthroughPOST/VFIO-Tools";
      flake = false;
    };

    # FIXME: Remove this when this PR is merged: https://github.com/haslersn/any-nix-shell/pull/34
    any-nix-shell = {
      url = "github:calebstewart/any-nix-shell/add-nix-develop-support";
      flake = false;
    };

    rofi-libvirt-mode = {
      url = "github:calebstewart/rofi-libvirt-mode?ref=d8d4387410606570f6cc5853cad4566dc3738834";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {self, ...}@inputs: inputs.nixpkgs.lib.attrsets.recursiveUpdate ({
    # Home Manager User Configurations
    homeConfigurations = import ./modules/users/home.nix {
      inherit inputs;
    };

    # Nixpkgs overlays
    overlays = import ./overlays/individual.nix {
      inherit inputs;
    };

    nixosModules = import ./modules/nixos/individual.nix {
      inherit inputs;
    };

    homeModules = import ./modules/home-manager/individual.nix {
      inherit inputs;
    };

    darwinModules = import ./modules/nix-darwin/individual.nix {
      inherit inputs;
    };
  } // (inputs.flake-utils.lib.eachDefaultSystem (system: {
    packages = import ./packages {
      inherit system inputs;
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    };
  }))) (import ./systems {
    inherit inputs;
  });
}
