{pkgs, lib, config, ...}:
let
  cfg = config.stewos.rofi;

  # Default rofi configuration settings
  defaultSettings = {
    configuration = {
      modi = "drun";
      show-icons = true;
      display-drun = "";
      drun-display-format = "{name}";
    };
  };

  # Default configuration file built from the module options
  defaultRofiConfig = pkgs.mkRofiConfig {
    name = "config.rasi";
    theme = cfg.theme;
    imports = cfg.imports;
    settings = lib.attrsets.recursiveUpdate defaultSettings cfg.settings;
  };

  # Bundle all themes and configs together so they can be installed together within
  # $XDG_DATA_HOME/rofi and $XDG_CONFIG_HOME/rofi as appropriate.
  extraPackages = pkgs.symlinkJoin {
    name = "rofi-config-bundle";
    paths = cfg.extraPackages ++ [defaultRofiConfig];

    postBuild = ''
      echo "Linking Rofi Scripts to /etc/rofi/scripts"
      mkdir -p $out/bin $out/etc/rofi/
      ln -s $out/bin $out/etc/rofi/scripts
    '';
  };
in {
  options.stewos.rofi = {
    enable = lib.mkEnableOption "rofi";
    package = lib.mkPackageOption pkgs "rofi-wayland" {};

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Extra packages containing Rofi configurations, themes or scripts to be installed.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Configuration in Nix attrset form (written to config.rasi)";
    };

    imports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    theme = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rofiThemes.stewos;
      description = "Rofi theme to use in the default configuration file";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install the selected rofi package
    home.packages = [cfg.package];

    # Write rofi data files
    xdg.dataFile."rofi" = {
      source = "${extraPackages}/share/rofi";
      recursive = true;
    };

    # Write rofi config file
    xdg.configFile."rofi" = {
      source = "${extraPackages}/etc/rofi";
      recursive = true;
    };
  };
}
