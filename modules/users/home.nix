{inputs}: 
let
  lib = inputs.nixpkgs.lib;
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  pathExists = builtins.pathExists;
  readDir = builtins.readDir;

  userFilter = name: type: (type == "directory" && (pathExists (./. + "${name}/home.nix")));
  userDirs = filterAttrs userFilter (readDir ./.);

  mkHomeManagerUser = name: {...}: {
    imports = [
      (./. + "/../home-manager/default.nix")
      (./. + "/${name}/home.nix")
    ];
  };
in mapAttrs (name: _type: mkHomeManagerUser name) userDirs
