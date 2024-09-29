{pkgs, lib, config, ...}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
  modulePaths = foldlAttrs (acc: name: _type: acc ++ [(./. + name)]) [] moduleDirs;
in {
  # Load all sub-modules
  imports = modulePaths;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Setup Nix configuration
  nix = {
    settings.auto-optimise-store = true;
    settings.experimental-features = ["nix-command" "flakes"];
  };

  # Enable mandb and nix documentation
  documentation = {
    enable = true;

    man = {
      enable = true;
      generateCaches = true;
    };
  };
}
