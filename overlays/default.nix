{pkgs, lib, config, ...}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  overlayFilter = name: type: type == "directory";
  overlayDirs = filterAttrs overlayFilter (readDir ./.);
in foldlAttrs (acc: name: _type: acc ++ [import (./. + name)]) [] overlayDirs
