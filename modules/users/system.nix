{lib, ...}:
let
  filterAttrs = lib.filterAttrs;
  pathExists = builtins.pathExists;
  readDir = builtins.readDir;

  userFilter = name: type: (type == "directory" && (pathExists (./. + "/${name}/system.nix")));
  userDirs = filterAttrs userFilter (readDir ./.);
  userConfigs = lib.attrsets.foldlAttrs (acc: name: _type: acc ++ [(./. + "/${name}/system.nix")]) [] userDirs;
in {
  imports = userConfigs;

  options.modules.users = {
    admin_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    base_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = {
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;

      # Add our home-manager modules to all configured users
      sharedModules = [
        (./. + "/../home-manager/default.nix")
      ];
    };
  };
}
