{inputs, ...}:
let
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;

  overlayFilter = name: type: type == "directory";
  overlayDirs = filterAttrs overlayFilter (readDir ./.);
in (mapAttrs (name: _type: import (./. + name)) overlayDirs) // {
  # Manually add the default module, which is a combination of all modules
  default = import ./default.nix;
}
