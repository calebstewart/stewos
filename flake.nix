{
  description = "Personal NixOS / Home-Manager / Nix-Darwin Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs?ref=nixpkgs-26.05-darwin";
    nix-colors.url = "github:misterio77/nix-colors";
    nur.url = "github:nix-community/NUR";
    nix-std.url = "github:chessai/nix-std";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixvim.url = "github:nix-community/nixvim";
    hyprsplit.url = "github:shezdy/hyprsplit";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin?ref=nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    mac-app-util = {
      url = "github:hraban/mac-app-util";
      # inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-cli = {
      url = "github:caelestia-dots/cli";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
      # The follows keeps the shell built against the same CLI we install --
      # without it the shell drags in a second copy of both the CLI and (via the
      # CLI) the shell itself.
      inputs.caelestia-cli.follows = "caelestia-cli";
    };

    # Qt6 platform theme + widget style for the Hyprland ecosystem (replaces
    # qt6ct/gtk3). Unreleased upstream; carries the same follows fragility as
    # llm-agents (see CLAUDE.md known failure modes).
    hyprqt6engine = {
      url = "github:hyprwm/hyprqt6engine";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The polkit agent from upstream rather than nixpkgs: upstream rewrote it
    # in hyprtoolkit (themed by hyprtoolkit.conf) without bumping the version,
    # so nixpkgs' "0.1.3" is still the old Qt dialog. Same follows caveat as
    # hyprqt6engine.
    hyprpolkitagent = {
      url = "github:hyprwm/hyprpolkitagent";
      inputs.nixpkgs.follows = "nixpkgs";
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

    embermug-tray = {
      url = "github:calebstewart/embermug-tray";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Packages the LLM coding agents, tracking their upstream releases more
    # closely than nixpkgs manages to.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Discord with Vencord, configured declaratively through home-manager.
    nixcord.url = "github:4evy/nixcord";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # ----------------------------------------------------------------------
      # nixpkgs instances
      # ----------------------------------------------------------------------

      # Which nixpkgs each target system is built from. Add a system here to get
      # "packages" and "formatter" outputs for it.
      nixpkgsFor = {
        x86_64-linux = nixpkgs;
        aarch64-darwin = inputs.nixpkgs-darwin;
      };

      # One nixpkgs instance per system, with the StewOS overlay applied.
      # Instantiated once and reused, so a host's system configuration and its
      # home configuration share an instance instead of evaluating nixpkgs twice.
      pkgsFor = lib.mapAttrs (
        system: src:
        import src {
          inherit system;

          config.allowUnfree = true;

          overlays = [
            (import ./overlays inputs)
            inputs.nur.overlays.default
          ];
        }
      ) nixpkgsFor;

      forAllSystems = f: lib.mapAttrs (_system: pkgs: f pkgs) pkgsFor;

      # ----------------------------------------------------------------------
      # Configuration builders
      #
      # "inputs" is handed to the module system once, here, via specialArgs.
      # Every module below modules/ and hosts/ is then a plain module file that
      # can be imported by path and takes { inputs, lib, config, pkgs, ... }.
      # ----------------------------------------------------------------------

      mkNixOSHost =
        {
          hostname,
          system,
          user,
          modules ? [ ],
        }:
        lib.nixosSystem {
          pkgs = pkgsFor.${system};
          specialArgs = { inherit inputs; };

          modules = [
            ./modules/nixos
            {
              networking.hostName = hostname;
              stewos.user = user;
            }
          ]
          ++ modules;
        };

      mkDarwinHost =
        {
          hostname,
          system,
          modules ? [ ],
        }:
        inputs.nix-darwin.lib.darwinSystem {
          pkgs = pkgsFor.${system};
          specialArgs = { inherit inputs; };

          modules = [
            ./modules/nix-darwin
            { networking.hostName = hostname; }
          ]
          ++ modules;
        };

      mkHome =
        {
          system,
          user,
          modules ? [ ],
        }:
        let
          isDarwin = lib.hasSuffix "darwin" system;
        in
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor.${system};
          extraSpecialArgs = { inherit inputs; };

          modules = [
            ./modules/home-manager
            {
              home.username = user.username;
              # Derived rather than passed in: the home directory and the
              # username cannot disagree if only one of them is written down.
              home.homeDirectory = (if isDarwin then "/Users/" else "/home/") + user.username;
              stewos.user = user;
            }
          ]
          ++ lib.optional isDarwin inputs.mac-app-util.homeManagerModules.default
          ++ modules;
        };

      # ----------------------------------------------------------------------
      # Users
      # ----------------------------------------------------------------------

      caleb = {
        username = "caleb";
        fullname = "Caleb Stewart";
        email = "caleb.stewart94@gmail.com";
      };

      calebWork = {
        username = "caleb.stewart";
        fullname = "Caleb Stewart";
        email = "caleb.stewart94@gmail.com";
        aliases.personal.email = "caleb.stewart94@gmail.com";
      };

      # ----------------------------------------------------------------------
      # Documentation
      # ----------------------------------------------------------------------

      # The whole site is built on one system. Reading an option tree never
      # builds anything, so the darwin module set evaluates perfectly well from
      # Linux -- which is what keeps this to a single job rather than a matrix
      # with a macOS runner in it.
      docsSystem = "x86_64-linux";

      scopePackages = forAllSystems (
        pkgs:
        lib.filterAttrs (
          _name: drv: lib.isDerivation drv && lib.meta.availableOn pkgs.stdenv.hostPlatform drv
        ) pkgs.stewos
      );

      docs = self.lib.docs.mkSite {
        pkgs = pkgsFor.${docsSystem};
        inherit self inputs;
        pkgsBySystem = pkgsFor;
        config = ./docs/flakedoc.toml;
        content = ./docs/content;

        # No stubs. The module trees are evaluated against a machine that does
        # not exist, and every option whose default reads "config" or "pkgs"
        # carries a defaultText, so nothing forces a value the stub would have
        # had to invent. Keep it that way: a stub is a value that shows up in
        # the rendered defaults of real options.
      };
    in
    {
      lib = import ./lib { inherit lib; } // {
        # The inputs the modules below are written against.
        #
        # StewOS modules reference specific inputs (stylix, nh, vfio-hooks, ...)
        # from inside "imports", and only specialArgs are available that early --
        # a _module.args value used in "imports" is an infinite recursion. So a
        # consuming flake has to hand these back in:
        #
        #   specialArgs = { inputs = stewos.lib.moduleInputs; };
        #
        # which also means "inputs" inside a StewOS module always refers to
        # StewOS's inputs. Pass your own under a different name.
        moduleInputs = inputs;
      };

      # The StewOS package scope, for use in other flakes:
      #   nixpkgs.overlays = [ stewos.overlays.default ];
      overlays.default = import ./overlays inputs;

      nixosModules.default = ./modules/nixos;
      homeModules.default = ./modules/home-manager;
      darwinModules.default = ./modules/nix-darwin;

      templates = import ./templates;

      # Only the derivations from the scope, and only the ones that can be built
      # on the system in question. The scope also holds builders (mkRofiConfig,
      # mkRofiTheme) which are functions, and Linux-only packages which must not
      # show up in the darwin output.
      #
      # "docs" is not one of those: it is this flake's own documentation site,
      # not a package the scope offers, and it exists on one system only.
      packages = scopePackages // {
        ${docsSystem} = scopePackages.${docsSystem} // {
          inherit docs;
        };
      };

      # Building the documentation is the check. It evaluates every module tree,
      # every host and every package's meta, and refuses to finish if an option
      # has no description -- which is a good deal more than "does it evaluate".
      checks.${docsSystem} = {
        inherit docs;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      nixosConfigurations = {
        framework-desktop = mkNixOSHost {
          hostname = "framework-desktop";
          system = "x86_64-linux";
          user = caleb // {
            groups = [ "nordvpn" ];
          };
          modules = [
            ./hosts/framework-desktop/hardware-configuration.nix
            ./hosts/framework-desktop/configuration.nix
          ];
        };

        framework16 = mkNixOSHost {
          hostname = "framework16";
          system = "x86_64-linux";
          user = caleb;
          modules = [
            ./hosts/framework16/hardware-configuration.nix
            ./hosts/framework16/configuration.nix
          ];
        };
      };

      darwinConfigurations = {
        huntress-mbp = mkDarwinHost {
          hostname = "huntress-mbp";
          system = "aarch64-darwin";
          modules = [ ./hosts/huntress-mbp/configuration.nix ];
        };
      };

      homeConfigurations = {
        "caleb@framework-desktop" = mkHome {
          system = "x86_64-linux";
          user = caleb;
          modules = [ ./hosts/framework-desktop/home.nix ];
        };

        "caleb@framework16" = mkHome {
          system = "x86_64-linux";
          user = caleb;
          modules = [ ./hosts/framework16/home.nix ];
        };

        "caleb.stewart@huntress-mbp" = mkHome {
          system = "aarch64-darwin";
          user = calebWork;
          modules = [ ./hosts/huntress-mbp/home.nix ];
        };
      };

      # "nix run .#<hostname>-vm" boots a host's configuration in a VM.
      apps.x86_64-linux = lib.mapAttrs' (
        hostname: host:
        lib.nameValuePair "${hostname}-vm" {
          type = "app";
          program = "${host.config.system.build.vm}/bin/run-${hostname}-vm";
          meta.description = "Boot the ${hostname} configuration in a VM";
        }
      ) self.nixosConfigurations;
    };
}
