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

  # This is used to make a common user options structure for both
  # NixOS and Home Manager.
  mkUserOptions =
    { lib, config }:
    {
      username = lib.mkOption {
        type = lib.types.str;
      };

      fullname = lib.mkOption {
        type = lib.types.str;
      };

      email = lib.mkOption {
        type = lib.types.str;
      };

      aliases = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              fullname = lib.mkOption {
                type = lib.types.str;
                default = config.stewos.user.fullname;
              };

              email = lib.mkOption {
                type = lib.types.str;
                default = config.stewos.user.email;
              };
            };
          }
        );
      };

      groups = lib.mkOption {
        description = "List of groups that should be applied to the default user";
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

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
      user,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;

      pkgs = mkNixpkgs system nixpkgs;

      modules = [
        {
          networking.hostName = hostname;
          stewos.user = user;
        }
        stewos.nixosModules.default
      ]
      ++ modules;
    };

  mkNixOSVirtualMachineApp =
    nixosConfiguration:
    let
      vm = nixosConfiguration.config.system.build.vm;
      hostname = nixosConfiguration.config.networking.hostName;
    in
    {
      type = "app";
      description = "Execute a virtual machine based on the this NixOS configuration";
      program = "${vm}/bin/run-${hostname}-vm";
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
      user,
      homeDirectory,
      isDarwin ? false,
    }:
    let
      nixpkgs-repo = if isDarwin then nixpkgs-darwin else nixpkgs;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkNixpkgs system nixpkgs-repo;

      modules = [
        stewos.homeModules.default
        {
          home.username = user.username;
          home.homeDirectory = homeDirectory;
          stewos.user = user;
        }
      ]
      ++ modules;
    };
}
