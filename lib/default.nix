{inputs, stewos, ...}:
let
  lib = inputs.nixpkgs.lib;
in rec {
  hypr = import ./hypr.nix {
    inherit inputs stewos lib;
  };

  rasi = import ./rasi/default.nix {
    inherit inputs stewos lib;
  };

  # Create a nixpkgs instance with stewos package overlays already
  # applied.
  mkNixpkgs = system: import inputs.nixpkgs {
    inherit system;

    overlays = [
      (final: prev: import ../packages/default.nix {
        inherit inputs stewos;
        pkgs = final;
      })
    ];
  };

  # Create a new NixOS system
  mkNixOSSystem = {system, hostname}: inputs.nixpkgs.lib.nixosSystem {
    inherit system;

    modules = [
      stewos.nixosModules.default
      inputs.home-manager.nixosModules.default
      ({...}: {
        home-manager.extraSpecialArgs = inputs // {
          inherit stewos inputs;
        };
      })
      (./. + "/../systems/${hostname}/hardware-configuration.nix")
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos inputs;
    };
  };

  mkNixOSVirtualMachineApp = nixosConfiguration: {
    type = "app";
    program = "${nixosConfiguration.config.system.build.vm}/bin/run-nixos-vm";
  };

  # Create a NixOS image of the given format
  mkNixOSImageGenerator = {system, hostname, format}: inputs.nixos-generators.nixosGenerate {
    inherit system format;

    modules = [
      stewos.nixosModules.default
      inputs.home-manager.nixosModules.default
      ({...}: {
        home-manager.extraSpecialArgs = inputs // {
          inherit stewos inputs;
        };
      })
      (./. + "/../systems/${hostname}/hardware-configuration.nix")
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos inputs;
    };
  };

  # Create a new Nix-Darwin System
  mkNixDarwinSystem = {system, hostname}: inputs.nix-darwin.lib.darwinSystem {
    inherit system;

    modules = [
      stewos.darwinModules.default
      inputs.home-manager.darwinModules.default
      ({...}: {
        home-manager.extraSpecialArgs = inputs // {
          inherit stewos inputs;
        };
      })
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos inputs;
    };
  };

  # Create a standalone home manager configuration using the StewOS default modules
  # and the given Home Manager module path.
  mkHomeManagerConfig = {system, modulePath}: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = mkNixpkgs system;

    modules = [
      stewos.homeModules.default
      modulePath
    ];

    extraSpecialArgs = inputs // {
      inherit stewos inputs;
    };
  };
}
