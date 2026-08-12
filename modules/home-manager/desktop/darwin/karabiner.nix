# Keyboard remapping on macOS.
#
# The profile is written whenever the desktop is enabled -- it also carries the
# menu bar and keyboard type settings -- but each remapping is gated on the
# option that asks for it.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.desktop;
  json = pkgs.formats.json { };

  # Caps Lock sends Escape. Deliberately one way: Escape keeps working as
  # Escape, which is the same thing "stewos.desktop.capsLockEscape" asks the
  # Linux side for.
  capsLockRules = lib.optionals cfg.capsLockEscape [
    {
      from = {
        key_code = "caps_lock";
      };
      to = [ { key_code = "escape"; } ];
    }
  ];

  # Left Command and left Alt trade places, so a keybinding prefix of "ALT"
  # falls on the key a Mac keyboard labels Command -- where the thumb already
  # is, and where a Linux keyboard would put Alt.
  commandAltRules = lib.optionals cfg.swapCommandAlt [
    {
      description = "Swap Left Command and Left Alt on internal keyboard only";
      manipulators = [
        {
          type = "basic";
          from = {
            key_code = "left_command";
            modifiers = {
              optional = [ "any" ];
            };
          };
          to = [ { key_code = "left_alt"; } ];
          # conditions = [
          #   {
          #     type = "device_if";
          #     identifiers = [ { is_built_in_keyboard = true; } ];
          #   }
          # ];
        }
        {
          type = "basic";
          from = {
            key_code = "left_alt";
            modifiers = {
              optional = [ "any" ];
            };
          };
          to = [ { key_code = "left_command"; } ];
          # conditions = [
          #   {
          #     type = "device_if";
          #     identifiers = [ { is_built_in_keyboard = true; } ];
          #   }
          # ];
        }
      ];
    }
  ];

  karabinerConfig = {
    global = {
      check_for_updates_on_startup = false;
      show_in_menu_bar = false;
      show_profile_name_in_menu_bar = false;
    };
    profiles = [
      {
        name = "Default";
        selected = true;
        simple_modifications = capsLockRules;
        complex_modifications = {
          rules = commandAltRules;
        };
        virtual_hid_keyboard = {
          keyboard_type_v2 = "ansi";
        };
      }
    ];
  };
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    xdg.configFile."karabiner/karabiner.json".source = json.generate "karabiner.json" karabinerConfig;
  };
}
