{ nixpkgs, ... }@inputs:
let
  # Shortcuts for library functions
  lib = nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;
  recursiveUpdate = lib.attrsets.recursiveUpdate;

  # Find all the templates, and load their properties
  templateDirs = filterAttrs (name: type: type == "directory") (readDir ./.);

  # Build all the outputs for each system
  templateOutputs = mapAttrs (name: _type: {
    "${name}" = import (./. + "/${name}/default.nix") inputs;
  }) templateDirs;
in
foldlAttrs (
  acc: _name: outputs:
  recursiveUpdate acc { templates = outputs; }
) { } templateOutputs
