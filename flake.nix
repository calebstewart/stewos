{
  description = "Personal NixOS / Home-Manager / Nix-Darwin Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs?ref=nixpkgs-25.05-darwin";
    nix-colors.url = "github:misterio77/nix-colors";
    nur.url = "github:nix-community/NUR";
    nix-std.url = "github:chessai/nix-std";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin?ref=nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stew-shell = {
      url = "github:calebstewart/stew-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    vfio-hooks = {
      url = "github:PassthroughPOST/VFIO-Tools";
      flake = false;
    };

    gh-actions-language-server = {
      url = "github:lttb/gh-actions-language-server";
      flake = false;
    };

    nh = {
      url = "github:nix-community/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@externalInputs:
    let
      inputs = externalInputs // {
        stewos = self;
      };

      # Base outputs which don't need any fancieness
      baseOutputs = {
        lib = import ./lib/default.nix inputs;
        nixosModules = import ./modules/nixos/individual.nix inputs;
        homeModules = import ./modules/home-manager/individual.nix inputs;
        darwinModules = import ./modules/nix-darwin/individual.nix inputs;
      };

      # Packages which must use the flake-utils helper
      packageOutputs = inputs.flake-utils.lib.eachDefaultSystem (system: {
        packages = import ./packages system inputs;
      });

      # System outputs which may also provide overlapping output keys, and must
      # be recursively merged with the above two attrsets.
      systemOutputs = import ./systems inputs;

      # Templates allow users to generate projects using StewOS from a template
      templateOutputs = import ./templates inputs;
    in
    inputs.nixpkgs.lib.attrsets.recursiveUpdate (
      baseOutputs // packageOutputs // templateOutputs
    ) systemOutputs;
}
