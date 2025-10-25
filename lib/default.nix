{
  stewos,
  home-manager,
  nixpkgs,
  nixpkgs-darwin,
  nur,
  ...
}@inputs:
let
  lib = nixpkgs.lib;
  importWithInputs = module: if builtins.isPath module then (import module inputs) else module;
  importAllWithInputs = modules: lib.lists.imap0 (_: module: importWithInputs module) modules;
in
rec {
  hypr = import ./hypr.nix inputs;
  rasi = import ./rasi/default.nix inputs;

  # Create a nixpkgs instance with stewos package overlays already
  # applied.
  mkNixpkgs =
    system: nixpkgs:
    import nixpkgs {
      inherit system;

      config.allowUnfree = true;

      overlays = [
        (final: prev: import ../packages/default.nix system inputs)
        nur.overlays.default
      ];
    };

  # Create a new NixOS system
  mkNixOSSystem =
    {
      hostname,
      system,
      modules,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;

      pkgs = mkNixpkgs system nixpkgs;

      modules = [
        { networking.hostName = hostname; }
        stewos.nixosModules.default
      ]
      ++ modules;
    };

  mkNixOSVirtualMachineApp = hostname: nixosConfiguration: {
    type = "app";
    description = "Execute a virtual machine based on the this NixOS configuration";
    program = "${nixosConfiguration.config.system.build.vm}/bin/run-${hostname}-vm";
  };

  # Create a NixOS image of the given format
  mkNixOSImageGenerator =
    {
      hostname,
      system,
      modules,
      format,
    }:
    inputs.nixos-generators.nixosGenerate {
      inherit system format;

      modules = [
        { network.hostName = hostname; }
        stewos.nixosModules.default
      ]
      ++ modules;
    };

  # Create a new Nix-Darwin System
  mkNixDarwinSystem =
    {
      hostname,
      system,
      modules,
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;

      pkgs = mkNixpkgs system nixpkgs-darwin;

      modules = [
        { networking.hostName = hostname; }
        stewos.darwinModules.default
        home-manager.darwinModules.default
      ]
      ++ modules;
    };

  # Create a standalone home manager configuration using the StewOS default modules
  # and the given Home Manager module path.
  mkHomeManagerConfig =
    {
      system,
      modules,
      username,
      homeDirectory,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkNixpkgs system nixpkgs;

      modules = [
        stewos.homeModules.default
        {
          home.username = username;
          home.homeDirectory = homeDirectory;
        }
      ]
      ++ modules;
    };
}
