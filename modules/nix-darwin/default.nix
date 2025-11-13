{
  home-manager,
  nur,
  stylix,
  ...
}@inputs:
{ pkgs, lib, ... }:
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
    home-manager.darwinModules.default
    nur.modules.darwin.default
    stylix.darwinModules.stylix
  ];

  # Setup Nix configuration
  nix = {
    optimise.automatic = true;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # Setup Nix Helper for easy building
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  # Enable mandb and nix documentation
  documentation = {
    enable = true;
    man.enable = true;
  };
}
