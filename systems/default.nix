{inputs, stewos, ...}:
let
  # Shortcuts for library functions
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;
  recursiveUpdate = lib.attrsets.recursiveUpdate;

  # Find all the systems, and load their properties
  systemDirs = filterAttrs (name: type: type == "directory") (readDir ./.);

  # Build all the outputs for each system
  systemOutputs = mapAttrs (name: _type: import (./. + "/${name}/system.nix") {
    inherit stewos inputs;
  }) systemDirs;

in foldlAttrs (acc: _name: outputs: recursiveUpdate acc outputs) {} systemOutputs
