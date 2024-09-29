{inputs, ...}:
let
  # Shortcuts for library functions
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;

  # Find all the systems, and load their properties
  systemDirs = filterAttrs (name: type: type == "directory") (readDir ./.);
  systemProps = mapAttrs (name: _type: import (./. + "/${name}/properties.nix")) systemDirs;

  # Filter out only the darwin systems
  darwinSystemProps = filterAttrs (name: props: props.isDarwin) systemProps;

  # Filter out only the linux systems
  linuxSystemProps = filterAttrs (name: props: !props.isDarwin) systemProps;

  # Collection of modules to load for NixOS. This is reused for NixOS systems
  # and for NixOS image generators to create (nearly) identical systems from
  # both targets.
  nixosModules = hostname: [
    (./. + "/../modules/users/system.nix")
    (./. + "/../modules/nixos/default.nix")
    (./. + "/${hostname}/hardware-configuration.nix")
    (./. + "/${hostname}/configuration.nix")
    inputs.home-manager.nixosModules.default
    inputs.nur.nixosModules.nur
  ];

  # Create a new NixOS system
  mkNixOSSystem = {system, hostname}: inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = nixosModules hostname;

    specialArgs = {
      inherit inputs system;
    };
  };

  # Create a NixOS image of the given format
  mkNixOSImageGenerator = {system, hostname, format}: inputs.nixos-generators.nixosGenerate {
    inherit system format;
    modules = nixosModules hostname;

    specialArgs = {
      inherit inputs system;
    };
  };

  # Create a new Nix-Darwin System
  mkNixDarwinSystem = {system, hostname}: inputs.nix-darwin.lib.darwinSystem {
    inherit system;

    modules = [
      (./. + "/../modules/nix-darwin/default.nix")
      (./. + "/${hostname}/configuration.nix")
      inputs.home-manager.darwinModules.default
    ];

    specialArgs = {
      inherit inputs system;
    };
  };

  nixosConfigurations = mapAttrs (hostname: props: mkNixOSSystem {
    inherit (props) system;
    inherit hostname;
  }) linuxSystemProps;
in {
  # Create NixOS configurations
  nixosConfigurations = nixosConfigurations;

  # Create nix-darwin configurations
  darwinConfigurations = mapAttrs (hostname: props: mkNixDarwinSystem {
    inherit (props) system;
    inherit hostname;
  }) darwinSystemProps;

} // inputs.flake-utils.lib.eachDefaultSystem (system: {
  # Create generators for all NixOS systems. These are (nearly) identical
  # to the associated NixOS system configurations.
  packages = mapAttrs (hostname: props: mkNixOSImageGenerator {
    inherit (props) system format;
    inherit hostname;
  }) linuxSystemProps;

  # Create shortcuts to run VMs of defined system configurations
  apps = mapAttrs (hostname: props: {
    type = "app";
    program = "${nixosConfigurations.${hostname}.config.system.build.vm}/bin/run-nixos-vm";
  }) linuxSystemProps;
})
