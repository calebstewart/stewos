{pkgs, lib, stewos, ...}:
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
  imports = modulePaths;

  nixpkgs = {
    # Allow unfree packages
    config.allowUnfree = true;

    # Include the StewOS packages under nixpkgs.stewos
    overlays = [
      (final: prev: {
        stewos = stewos.packages.${pkgs.system};
      })
    ];
  };

  # Setup Nix configuration
  nix = {
    settings.auto-optimise-store = true;
    settings.experimental-features = ["nix-command" "flakes"];
  };

  # Setup Nix Helper for easy building
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  # Clean tmpfs during system boot
  boot.tmp.cleanOnBoot = true;

  # Enable mandb and nix documentation
  documentation = {
    enable = true;

    man = {
      enable = true;
      generateCaches = true;
    };
  };
}
