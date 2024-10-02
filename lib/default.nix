{inputs, stewos, ...}:
let

in rec {
  # Create a nixpkgs instance with stewos package overlays already
  # applied.
  mkNixpkgs = system: import inputs.nixpkgs {
    inherit system;

    overlays = [
      (final: prev: {
        stewos = stewos.packages.${system};
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
          inherit stewos;
        };
      })
      (./. + "/../systems/${hostname}/hardware-configuration.nix")
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos;
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
          inherit stewos;
        };
      })
      (./. + "/../systems/${hostname}/hardware-configuration.nix")
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos;
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
          inherit stewos;
        };
      })
      (./. + "/../systems/${hostname}/configuration.nix")
    ];

    specialArgs = inputs // {
      inherit stewos;
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
      inherit stewos;
    };
  };
}
