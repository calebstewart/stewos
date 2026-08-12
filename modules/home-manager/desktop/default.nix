{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  defaultWallpaper = pkgs.fetchurl {
    url = "https://i.redd.it/187ouknqbs051.jpg";
    sha256 = "sha256-3x0pvEWWM2SqxzR16Hv7+xGxMqkEPQE5kcUY84kEIrw=";
  };

  # Hyprland spawns this during compositor init when "startLocked" is set (see
  # "--locked-cmd" in hyprland.nix). The session is already force-locked by the
  # time it runs; its job is to hand that force-lock over to the real locker.
  #
  # caelestia's locker lives inside caelestia-shell, which systemd only starts
  # once graphical-session.target is up, so its IPC socket does not exist yet.
  # Poll until it answers instead of racing it: a single early attempt is what
  # made the old ExecStartPost fail roughly half the time.
  caelestiaLockCommand = pkgs.writeShellScript "caelestia-lock-session" ''
    tries=0
    while [ "$tries" -lt 300 ]; do
      if ${lib.getExe config.programs.caelestia.cli.package} shell lock lock >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.2
      tries=$((tries + 1))
    done
    echo "caelestia-shell did not accept the lock IPC within 60s;" \
         "the session is still force-locked with no locker attached" >&2
    exit 1
  '';
in
{
  imports = [
    # inputs.stew-shell.homeModules.default
    inputs.caelestia-shell.homeManagerModules.default
    inputs.noctalia.homeModules.default

    ./hyprland.nix
    ./fonts.nix
    ./gtk.nix
    # ./hypridle.nix
    # ./hyprlock.nix
    # ./hyprpaper.nix
    ./polkit.nix
    ./qt.nix
    # ./rofi.nix
    ./xdg.nix
    ./aerospace.nix
    ./raycast.nix
    ./autoraise.nix
    ./karabiner.nix
  ];

  options.stewos.desktop = {
    enable = lib.mkEnableOption "Graphical Desktop";
    startLocked = lib.mkEnableOption "Start Desktop in Locked State";

    lockCommand = lib.mkOption {
      description = ''
        Command Hyprland spawns during compositor init when "startLocked" is
        set, to bring up the session locker. It runs against an already
        force-locked session, so it must tolerate the shell that provides the
        locker not being up yet. Defaults to the caelestia locker on Linux.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
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
                description = ''
                  The Hyprland dispatcher to use for this binding. In addition to
                  the dispatcher names mapped onto the Lua API in the Hyprland
                  module, "exec" runs a package, "rofi" opens rofi with a set of
                  modes, and "lua" evaluates the raw expression in "lua".
                '';
                type = lib.types.str;
                default = "exec";
              };

              lua = lib.mkOption {
                description = ''
                  Raw Lua expression evaluated as the dispatcher, used when
                  "dispatcher" is set to "lua". For example
                  "hl.dsp.window.move({ workspace = 3 })".
                '';
                type = lib.types.str;
                default = "";
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
      {
        assertion = !cfg.startLocked || cfg.lockCommand != null;
        message = ''
          stewos.desktop.startLocked requires stewos.desktop.lockCommand.
          Hyprland force-locks the session during init, so without a command to
          bring up a locker the session boots to an unlockable "your locker app
          crashed or didn't start" screen.
        '';
      }
    ];

    # Stew-Shell is only valid for Linux hosts
    # stew-shell.enable = pkgs.stdenv.isLinux;

    programs.noctalia = {
      enable = false; # pkgs.stdenv.isLinux;

      settings = {
        wallpaper = {
          enabled = true;
          default.path = cfg.wallpaper;
        };
      };
    };

    programs.caelestia = {
      enable = pkgs.stdenv.isLinux;
      systemd.enable = true;
      cli.enable = true;

      settings = {
        paths.wallpaperDir = "~/Pictures/Wallpapers";

        # Defaults to IP location
        services.weatherLocation = lib.mkDefault "";

        # We run a single-user system, so logging out is just locking the screen.
        session.commands.logout = [
          "loginctl"
          "lock-session"
        ];
      };
    };

    # Hyprland drives the startup lock itself via "--locked-cmd" (see
    # hyprland.nix), so this is not a systemd ExecStartPost. That matters for
    # more than tidiness: Hyprland force-locks at init, and only exempts the
    # incoming ext-session-lock from its "Cannot re-lock" check when it was
    # given a locker command. A lock arriving from anywhere else is denied with
    # a protocol error that kills the shell.
    stewos.desktop.lockCommand = lib.mkIf pkgs.stdenv.isLinux (lib.mkDefault "${caelestiaLockCommand}");

    # Setup a volume control application for Linux
    home.packages = lib.mkIf pkgs.stdenv.isLinux (
      with pkgs;
      [
        pwvucontrol
      ]
    );

    # Electron reads this natively to pick its Ozone backend, which is the
    # supported replacement for per-package "commandLineArgs" overrides. The
    # Hyprland module copies home.sessionVariables into the systemd user
    # environment, so the whole graphical session inherits it.
    home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };

    home.file."Pictures/Wallpapers/wallpaper.jpg".source = cfg.wallpaper;

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
