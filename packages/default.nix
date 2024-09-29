{inputs, system, pkgs, ...}:
let
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;

  packageFilter = name: type: type == "directory";
  packageDirs = filterAttrs packageFilter (readDir ./.);
in (mapAttrs (name: _type: (import (./. + "/${name}") {
  inherit inputs system pkgs;
})) packageDirs)
