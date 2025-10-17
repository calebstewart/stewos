system:
{ nixpkgs, stewos, ... }@inputs:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};
  mapAttrs = lib.mapAttrs;
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;

  packageFilter = name: type: type == "directory";
  packageDirs = filterAttrs packageFilter (readDir ./.);

  callPackage = pkgs.lib.callPackageWith overlayedPkgs;
  newPackages = (mapAttrs (name: _type: (callPackage (./. + "/${name}") { })) packageDirs);
  overlayedPkgs = pkgs.lib.recursiveUpdate pkgs (
    newPackages
    // {
      inherit inputs stewos callPackage;
    }
  );
in
newPackages
