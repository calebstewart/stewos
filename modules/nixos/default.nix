{pkgs, lib, stewos, home-manager, nur, inputs, ...}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
  modulePaths = foldlAttrs (acc: name: _type: acc ++ [(./. + "/${name}")]) [] moduleDirs;
in {
  # DO NOT MODIFY
  system.stateVersion = "24.05";

  # Load all sub-modules
  imports = modulePaths ++ [
    home-manager.nixosModules.default
    nur.modules.nixos.default
  ];

  nixpkgs = {
    # Allow unfree packages
    config.allowUnfree = true;

    # Include the StewOS packages under nixpkgs.stewos
    overlays = [
      (final: prev: import ../../packages/default.nix {
        inherit inputs stewos;
        pkgs = final;
      })
    ];
  };

  # Setup Nix configuration
  nix = {
    settings.auto-optimise-store = true;
    settings.experimental-features = ["nix-command" "flakes"];
  };

  boot = {
    # Clean tmpfs during system boot
    tmp.cleanOnBoot = true;

    # Use systemd-boot
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Use a pretty spinner animation for the boot process
    plymouth = {
      enable = true;
      theme = "spin";
      themePackages = [
        (pkgs.adi1090x-plymouth-themes.override {
          selected_themes = ["spin"];
        })
      ];
    };
  };

  # Setup Nix Helper for easy building
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  # This is needed or else home-manager fails to start later
  programs.dconf.enable = true;

  # We do not use sudo
  security.sudo.enable = false;

  # Configure doas to allow the administrators
  security.doas.enable = true;

  # Enable mandb and nix documentation
  documentation = {
    enable = true;

    man = {
      enable = true;
      generateCaches = true;
    };
  };

  # Setup embedded home manager
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;

    # Add our home-manager modules to all configured users
    sharedModules = [stewos.homeModules.default];
  };
}
