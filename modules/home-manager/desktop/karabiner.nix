{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.desktop;
  json = pkgs.formats.json { };
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
        simple_modifications = [
          {
            from = {
              key_code = "caps_lock";
            };
            to = [ { key_code = "escape"; } ];
          }
        ];
        complex_modifications = {
          rules = [
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
