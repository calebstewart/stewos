{stewos, home-manager, ...}@inputs:
let
  hardwareConfigurationFor = hostname: (
    import (./. + "/../systems/${hostname}/hardware-configuration.nix") inputs
  );

  configurationFor = hostname: (
    import (./. + "/../systems/${hostname}/configuration.nix") inputs
  );
in rec {
  hypr = import ./hypr.nix inputs;
  rasi = import ./rasi/default.nix inputs;

  # Create a nixpkgs instance with stewos package overlays already
  # applied.
  mkNixpkgs = system: import inputs.nixpkgs {
    inherit system;

    config.allowUnfree = true;

    overlays = [
      (final: prev: import ../packages/default.nix system inputs)
    ];
  };

  # Create a new NixOS system
  mkNixOSSystem = {system, hostname}: inputs.nixpkgs.lib.nixosSystem {
    inherit system;

    pkgs = mkNixpkgs system;

    modules = [
      stewos.nixosModules.default
      home-manager.nixosModules.default
      (hardwareConfigurationFor hostname)
      (configurationFor hostname)
    ];
  };

  mkNixOSVirtualMachineApp = nixosConfiguration: {
    type = "app";
    description = "Execute a virtual machine based on the this NixOS configuration";
    program = "${nixosConfiguration.config.system.build.vm}/bin/run-nixos-vm";
  };

  # Create a NixOS image of the given format
  mkNixOSImageGenerator = {system, hostname, format}: inputs.nixos-generators.nixosGenerate {
    inherit system format;

    modules = [
      stewos.nixosModules.default
      home-manager.nixosModules.default
      (hardwareConfigurationFor hostname)
      (configurationFor hostname)
    ];
  };

  # Create a new Nix-Darwin System
  mkNixDarwinSystem = {system, hostname}: inputs.nix-darwin.lib.darwinSystem {
    inherit system;

    modules = [
      stewos.darwinModules.default
      home-manager.darwinModules.default
      (configurationFor hostname)
    ];
  };

  # Create a standalone home manager configuration using the StewOS default modules
  # and the given Home Manager module path.
  mkHomeManagerConfig = {system, modulePath}: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = mkNixpkgs system;

    modules = [
      stewos.homeModules.default
      (import modulePath inputs)
    ];
  };
}
