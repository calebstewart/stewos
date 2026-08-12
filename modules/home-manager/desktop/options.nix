# The whole "stewos.desktop" settings surface, in one file.
#
# Nothing here names a compositor or a window manager. Hyprland runs the show
# on Linux and Aerospace on macOS, but that is an implementation detail of
# ./linux and ./darwin -- a host describes what it wants, and the backend for
# the platform it is built for works out how to ask for it.
{
  pkgs,
  lib,
  ...
}:
let
  vocabulary = import ./vocabulary.nix;

  commandType = lib.types.submodule {
    options = {
      package = lib.mkOption {
        description = "Package providing the program to run.";
        type = lib.types.package;
      };

      target = lib.mkOption {
        description = ''
          Name of the binary inside "package" to run. Defaults to the
          package's main program.
        '';
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      args = lib.mkOption {
        description = "Arguments appended to the command line.";
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  bindingType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        description = ''
          Whether to bind this key combination. Set to false to switch off a
          binding StewOS provides by default.
        '';
        type = lib.types.bool;
        default = true;
      };

      key = lib.mkOption {
        description = ''
          Key to bind, under a name that means the same thing on every
          platform: a letter ("h"), a digit ("1"), a function key ("f5"), an
          arrow ("left", "right", "up", "down"), a named key ("enter",
          "space", "tab", "escape", "backspace", "delete", "minus", "equal",
          "slash", "comma", "period", "semicolon"), or a media key
          ("volume-up", "volume-down", "volume-mute", "brightness-up",
          "brightness-down").

          A name the platform's backend does not recognise fails the build,
          rather than producing a binding that silently never fires.
        '';
        type = lib.types.str;
        example = "h";
      };

      modifiers = lib.mkOption {
        description = ''
          Modifiers held alongside "stewos.desktop.modifier". Order does not
          matter; each backend renders them in its own fixed order.
        '';
        type = lib.types.listOf (lib.types.enum vocabulary.modifiers);
        default = [ ];
        example = [ "shift" ];
      };

      useModifier = lib.mkOption {
        description = ''
          Whether "stewos.desktop.modifier" is part of the combination. Set to
          false for keys that have to fire on their own, such as the media
          keys along the top of a laptop keyboard.
        '';
        type = lib.types.bool;
        default = true;
      };

      platforms = lib.mkOption {
        description = ''
          Platforms this binding applies to. On any other platform it is
          quietly dropped instead of rejected, which is how a binding whose
          command only exists on one operating system can live in
          configuration shared between machines.
        '';
        type = lib.types.listOf (
          lib.types.enum [
            "linux"
            "darwin"
          ]
        );
        default = [
          "linux"
          "darwin"
        ];
      };

      action = lib.mkOption {
        description = ''
          A window management action to perform. Set exactly one of "action"
          or "command".

          Not every platform can perform every action. One that cannot fails
          the build with the list of actions it does support, so restrict the
          binding with "platforms" if it is meant for a single machine.
        '';
        type = lib.types.nullOr (lib.types.enum vocabulary.actions);
        default = null;
        example = "focus-window";
      };

      direction = lib.mkOption {
        description = ''
          Which way the directional actions ("focus-window", "move-window",
          "focus-monitor", "move-window-to-monitor") point.
        '';
        type = lib.types.nullOr (lib.types.enum vocabulary.directions);
        default = null;
      };

      workspace = lib.mkOption {
        description = ''
          Which workspace the workspace actions ("workspace",
          "move-window-to-workspace") act on.
        '';
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
      };

      command = lib.mkOption {
        description = ''
          Run a program. Set exactly one of "action" or "command".

          The command line is built from the package identically everywhere,
          so this covers ordinary programs. Launching a macOS application
          bundle is a different operation and is not expressible here; the two
          cases StewOS needs, a terminal and a launcher, are actions instead.
        '';
        type = lib.types.nullOr commandType;
        default = null;
      };
    };
  };

  monitorType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        description = ''
          The monitor's identity as it reports it over EDID: vendor, model and
          serial number. "wlr-randr" or the compositor's own monitor listing
          will print it.
        '';
        type = lib.types.str;
        example = "Dell Inc. DELL U2723QE 55L01P3";
      };

      scale = lib.mkOption {
        description = ''
          Fractional scaling factor. The monitor's logical size is its
          resolution divided by this, and logical pixels are what "position"
          is measured in.
        '';
        type = lib.types.float;
        default = 1.0;
      };

      position = lib.mkOption {
        description = ''
          Where this monitor's top-left corner sits in the desktop layout, in
          logical (post-scaling) pixels.
        '';
        type = lib.types.submodule {
          options = {
            x = lib.mkOption {
              description = "Horizontal offset, in logical pixels.";
              type = lib.types.int;
              default = 0;
            };

            y = lib.mkOption {
              description = "Vertical offset, in logical pixels.";
              type = lib.types.int;
              default = 0;
            };
          };
        };
      };

      resolution = lib.mkOption {
        description = ''
          Resolution to drive the monitor at, or "preferred" to take the mode
          the monitor itself advertises as best.
        '';
        default = "preferred";
        type = lib.types.either (lib.types.enum [ "preferred" ]) (
          lib.types.submodule {
            options = {
              width = lib.mkOption {
                description = "Width in physical pixels.";
                type = lib.types.int;
              };

              height = lib.mkOption {
                description = "Height in physical pixels.";
                type = lib.types.int;
              };
            };
          }
        );
      };
    };
  };

  keyboardType = lib.types.submodule {
    options = {
      layout = lib.mkOption {
        description = "Keyboard layout for this device.";
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "us";
      };

      variant = lib.mkOption {
        description = "Layout variant for this device.";
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      capsLockEscape = lib.mkOption {
        description = ''
          Override "stewos.desktop.capsLockEscape" for this keyboard only.
          Null leaves the session-wide setting in force.
        '';
        type = lib.types.nullOr lib.types.bool;
        default = null;
      };
    };
  };

  fontType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        description = "Family name, as fontconfig and the toolkits know it.";
        type = lib.types.str;
      };

      package = lib.mkOption {
        description = "Package providing the family.";
        type = lib.types.package;
      };

      size = lib.mkOption {
        description = "Point size.";
        type = lib.types.int;
        default = 11;
      };
    };
  };
in
{
  options.stewos.desktop = {
    enable = lib.mkEnableOption "Graphical Desktop";

    startLocked = lib.mkEnableOption ''
      bringing the session up locked, so a machine that boots unattended lands
      on a lock screen rather than on your desktop. Linux only
    '';

    lockCommand = lib.mkOption {
      description = ''
        Command run to bring up the session locker when "startLocked" is set.
        Filled in by the platform backend.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      visible = false;
    };

    capsLockEscape = lib.mkEnableOption "sending Escape when Caps Lock is pressed";

    swapCommandAlt = lib.mkEnableOption ''
      swapping the left Command and left Alt keys on macOS. Worth turning on
      when "stewos.desktop.modifier" is "ALT", so the prefix falls under your
      thumb on the key a Mac keyboard labels Command
    '';

    terminal = lib.mkPackageOption pkgs "alacritty" { };

    modifier = lib.mkOption {
      description = ''
        Modifier held for the global keybinding prefix. Each platform renders
        it in its own vocabulary -- "SUPER" is the Command key on macOS.
      '';
      type = lib.types.enum [
        "SUPER"
        "ALT"
        "CTRL"
        "SHIFT"
      ];
      default = "SUPER";
    };

    monitors = lib.mkOption {
      description = ''
        Monitor layout. Any monitor not described here is placed automatically
        at its preferred resolution. Linux only; macOS arranges displays
        itself.
      '';
      default = [ ];
      type = lib.types.listOf monitorType;
    };

    keyboards = lib.mkOption {
      description = ''
        Per-keyboard overrides, keyed by the device name the session reports.
        A laptop whose built-in keyboard enumerates as its own input device
        often needs one, because the session-wide keyboard settings do not
        reach it. Only the fields you set are overridden. Linux only.
      '';
      default = { };
      type = lib.types.attrsOf keyboardType;
      example = lib.literalExpression ''
        {
          "framework-laptop-16-keyboard-module---ansi-keyboard".capsLockEscape = true;
        }
      '';
    };

    wallpaper = lib.mkOption {
      description = "Path to a wallpaper.";
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "https://i.redd.it/187ouknqbs051.jpg";
        sha256 = "sha256-3x0pvEWWM2SqxzR16Hv7+xGxMqkEPQE5kcUY84kEIrw=";
      };
      defaultText = lib.literalMD "a bundled default image";
    };

    fonts = {
      ui = lib.mkOption {
        description = "Font used for interface text across the toolkits.";
        type = fontType;
        default = {
          name = "Roboto";
          package = pkgs.roboto;
          size = 11;
        };
        defaultText = lib.literalExpression ''
          {
            name = "Roboto";
            package = pkgs.roboto;
            size = 11;
          }
        '';
      };

      monospace = lib.mkOption {
        description = "Font used wherever the width of a character matters.";
        type = fontType;
        default = {
          name = "JetBrains Mono";
          package = pkgs.jetbrains-mono;
          size = 11;
        };
        defaultText = lib.literalExpression ''
          {
            name = "JetBrains Mono";
            package = pkgs.jetbrains-mono;
            size = 11;
          }
        '';
      };
    };

    bindings = lib.mkOption {
      description = ''
        Keybindings, keyed by a name of your choosing. Each names a key, the
        modifiers held with it, and either an "action" or a "command" to run.

        The names are the point: StewOS contributes its own bindings under
        this option, so a host can retarget one by setting its "key", or drop
        it entirely with "enable = false", without having to restate the rest.
      '';
      default = { };
      type = lib.types.attrsOf bindingType;
      example = lib.literalExpression ''
        {
          # Move the launcher onto a different key
          launcher.key = "space";

          # Stop binding the power menu
          power-menu.enable = false;

          # Add one of your own
          notes = {
            key = "n";
            modifiers = [ "shift" ];
            command.package = pkgs.obsidian;
          };
        }
      '';
    };
  };
}
