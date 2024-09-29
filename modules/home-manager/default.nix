{pkgs, lib, config, ...}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
  modulePaths = foldlAttrs (acc: name: _type: acc ++ [(./. + name)]) [] moduleDirs;
in {
  # DO NOT MODIFY
  home.stateVersion = "24.05";

  # Load all sub-modules
  imports = modulePaths;
}
