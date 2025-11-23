{
  nix-colors,
  stylix,
  stewos,
  ...
}@inputs:
{
  lib,
  config,
  ...
}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
  modulePaths = foldlAttrs (
    acc: name: _type:
    acc ++ [ (import (./. + "/${name}") inputs) ]
  ) [ ] moduleDirs;
in
{
  # Load all sub-modules
  imports = modulePaths ++ [
    nix-colors.homeManagerModules.default
    stylix.homeModules.stylix
  ];

  # Common user options
  options.stewos.user = stewos.lib.mkUserOptions {
    inherit lib config;
  };

  config = {
    home.stateVersion = "25.05";
  };
}
