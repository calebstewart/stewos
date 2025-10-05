{lib, nix-colors, nur, config, ...}:
let
  filterAttrs = lib.filterAttrs;
  readDir = builtins.readDir;
  foldlAttrs = lib.attrsets.foldlAttrs;

  moduleFilter = name: type: type == "directory";
  moduleDirs = filterAttrs moduleFilter (readDir ./.);
  modulePaths = foldlAttrs (acc: name: _type: acc ++ [(./. + "/${name}")]) [] moduleDirs;
in {
  # Load all sub-modules
  imports = modulePaths ++ [
    nix-colors.homeManagerModules.default
    nur.modules.homeManager.default
  ];

  options.stewos.user = {
    fullName = lib.mkOption {
      type = lib.types.str;
    };

    email = lib.mkOption {
      type = lib.types.str;
    };

    aliases = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          fullName = lib.mkOption {
            type = lib.types.str;
            default = config.stewos.user.fullName;
          };

          email = lib.mkOption {
            type = lib.types.str;
            default = config.stewos.user.email;
          };
        };
      });
    };
  };

  config = {
    home.stateVersion = "24.05";
  };
}
