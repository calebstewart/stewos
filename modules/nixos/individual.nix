{inputs, ...}:
let
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
in (mapAttrs (name: _type: import (./. + "/${name}")) moduleDirs) // {
  # Manually add the default module, which is a combination of all modules
  default = import ./default.nix;
}
