{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  imports = [
    ./fonts.nix
    ./gtk.nix
    ./hypridle.nix
    ./hyprland.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./polkit.nix
    ./qt.nix
    ./rofi.nix
    ./swaync.nix
    ./waybar/default.nix
    ./xdg.nix
  ];

  options.stewos.desktop = {
    enable = lib.mkEnableOption "Graphical Desktop";
    swapEscape = lib.mkEnableOption "Swap Escape and Caps Lock";
    terminal = lib.mkPackageOption pkgs "alacritty" {};

    modifier = lib.mkOption {
      description = "Name of the key used for the global key combination modifier prefix.";
      type = lib.types.str;
      default = "SUPER";
    };

    monitors = lib.mkOption {
      description = "List of configured monitor settings";
      default = [];
      type = lib.types.listOf (lib.types.submodule {
        options = {
          description = lib.mkOption { type = lib.types.str; };
          scale = lib.mkOption { type = lib.types.float; default = 1.0; };

          position = lib.mkOption {
            type = lib.types.submodule {
              options = {
                x = lib.mkOption { type = lib.types.int; default = 0; };
                y = lib.mkOption { type = lib.types.int; default = 0; };
              };
            };
          };

          resolution = lib.mkOption {
            default = "preferred";
            type = lib.types.either (lib.types.enum ["preferred"]) (lib.types.submodule {
              options = {
                width = lib.mkOption { type = lib.types.int; };
                height = lib.mkOption { type = lib.types.int; };
              };
            });
          };
        };
      });
    };

    idle = {
      dimSeconds = lib.mkOption {
        description = "Number of idle seconds before the default output is dimmed.";
        default = 30;
        type = lib.types.int;
      };

      lockSeconds = lib.mkOption {
        description = "Number of idle seconds before the user session is locked.";
        default = 45;
        type = lib.types.int;
      };

      sleepSeconds = lib.mkOption {
        description = "Number of idle seconds before the host is suspended.";
        default = 60;
        type = lib.types.int;
      };
    };

    notifications = {
      enableSound = lib.mkOption {
        description = "Enable a sound for each notification";
        default = true;
        type = lib.types.bool;
      };

      volume = lib.mkOption {
        description = "The volume (0-1.0) of the notification sound";
        default = 0.5;
        type = lib.types.float;
      };

      soundTheme = lib.mkPackageOption pkgs "sound-theme-freedesktop" {};
    };

    wallpaper = lib.mkOption {
      description = "Path to a wallpaper.";
      type = lib.types.path;
    };

    bindings = lib.mkOption {
      description = "Mapping of modifiers and keys to bindings";
      default = {};
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            description = "Enable the keybinding";
            type = lib.types.bool;
            default = true;
          };

          dispatcher = lib.mkOption {
            description = "The Hyprland dispatcher to use for this binding";
            type = lib.types.str;
            default = "exec";
          };

          target = lib.mkOption {
            description = "The target binary name for exec bindings";
            type = lib.types.nullOr lib.types.str;
            default = null;
          };

          args = lib.mkOption {
            description = "List of arguments added to exec bindings command line";
            type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
            default = [];
          };

          modes = lib.mkOption {
            description = "List of Rofi mode names or script mode packages to show";
            type = lib.types.listOf (lib.types.either lib.types.str lib.types.package);
          };

          theme = lib.mkOption {
            description = "Rofi theme name or theme package to use";
            type = lib.types.nullOr (lib.types.either lib.types.str lib.types.package);
            default = null;
          };

          package = lib.mkOption {
            type = lib.types.package;
            description = "The package to execute for exec bindings";
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      pwvucontrol
    ];
  };
}
