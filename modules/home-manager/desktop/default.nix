{ stew-shell, caelestia-shell, ... }@inputs:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  hyprland = import ./hyprland.nix inputs;
  defaultWallpaper = pkgs.fetchurl {
    url = "https://i.redd.it/187ouknqbs051.jpg";
    sha256 = "sha256-3x0pvEWWM2SqxzR16Hv7+xGxMqkEPQE5kcUY84kEIrw=";
  };
in
{
  imports = [
    hyprland
    stew-shell.homeModules.default
    caelestia-shell.homeManagerModules.default

    ./fonts.nix
    ./gtk.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./polkit.nix
    ./qt.nix
    ./rofi.nix
    ./xdg.nix
    ./aerospace.nix
    ./raycast.nix
    ./autoraise.nix
  ];

  options.stewos.desktop = {
    enable = lib.mkEnableOption "Graphical Desktop";
    startLocked = lib.mkEnableOption "Start Desktop in Locked State";
    swapEscape = lib.mkEnableOption "Swap Escape and Caps Lock";
    terminal = lib.mkPackageOption pkgs "alacritty" { };

    modifier = lib.mkOption {
      description = "Name of the key used for the global key combination modifier prefix.";
      type = lib.types.str;
      default = "SUPER";
    };

    monitors = lib.mkOption {
      description = "List of configured monitor settings";
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption { type = lib.types.str; };
            scale = lib.mkOption {
              type = lib.types.float;
              default = 1.0;
            };

            position = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  x = lib.mkOption {
                    type = lib.types.int;
                    default = 0;
                  };
                  y = lib.mkOption {
                    type = lib.types.int;
                    default = 0;
                  };
                };
              };
            };

            resolution = lib.mkOption {
              default = "preferred";
              type = lib.types.either (lib.types.enum [ "preferred" ]) (
                lib.types.submodule {
                  options = {
                    width = lib.mkOption { type = lib.types.int; };
                    height = lib.mkOption { type = lib.types.int; };
                  };
                }
              );
            };
          };
        }
      );
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
        default = pkgs.stdenv.isLinux;
        type = lib.types.bool;
      };

      volume = lib.mkOption {
        description = "The volume (0-1.0) of the notification sound";
        default = 0.5;
        type = lib.types.float;
      };

      soundTheme = lib.mkPackageOption pkgs "sound-theme-freedesktop" { };
    };

    wallpaper = lib.mkOption {
      description = "Path to a wallpaper.";
      type = lib.types.path;
      default = defaultWallpaper;
    };

    bindings = lib.mkOption {
      description = "Mapping of modifiers and keys to bindings";
      default = { };
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
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
                default = [ ];
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
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.monitors == [ ] || !pkgs.stdenv.isDarwin;
        message = "Monitor layouts cannot be configured for MacOS";
      }
      {
        assertion = !cfg.notifications.enableSound || !pkgs.stdenv.isDarwin;
        message = "Notification sounds cannot be configured in home-manager for MacOS";
      }
      {
        assertion = cfg.bindings == { } || !pkgs.stdenv.isDarwin;
        message = "Bindings are not supported for MacOS";
      }
    ];

    # Stew-Shell is only valid for Linux hosts
    # stew-shell.enable = pkgs.stdenv.isLinux;

    programs.caelestia = {
      enable = pkgs.stdenv.isLinux;

      systemd = {
        enable = true;
        target = "hyprland-session.target";
      };

      cli.enable = true;
    };

    # Setup a volume control application for Linux
    home.packages = lib.mkIf pkgs.stdenv.isLinux (
      with pkgs;
      [
        pwvucontrol
      ]
    );

    # Set the wallpaper for darwin systems
    home.activation.setDarwinWallpaper = lib.mkIf pkgs.stdenv.isDarwin (
      let
        osascript = "/usr/bin/osascript";
        scriptFile = pkgs.writeTextFile {
          name = "set-wallpaper.osa";
          text = ''
            tell application "System Events"
              tell every desktop
                set picture to "${cfg.wallpaper}"
              end tell
            end tell
          '';
        };
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.strings.escapeShellArgs [
          osascript
          scriptFile
        ]
      )
    );
  };
}
