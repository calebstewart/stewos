{lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    # Configure Locker
    programs.hyprlock = {
      enable = true;

      settings = {
        general = {
          disable_loading_bar = true;
          grace = 5;
        };

        background = [{
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }];

        input-field = with config.colorScheme.palette; [{
          size = "250, 60";
          outline_thickness = 4;
          dots_size = 0.2;
          dots_spacing = 0.15;
          dots_center = true;
          outer_color = "rgb(${base02})";
          inner_color = "rgb(${base00})";
          font_color = "rgb(${base05})";
          check_color = "rgb(${base0A})";
          fail_color = "rgb(${base08})";
          capslock_color = "rgb(${base09})";
          bothlock_color = "rgb(${base09})";
          numlock_color = -1;
          swap_font_color = false;
          fail_text = ''<i>$FAIL <b>($ATTEMPTS)</b></i>'';
          fail_transition = 500;
          fade_on_empty = true;
          font_family = "JetBrains Mono Nerd Font Mono";
          placeholder_text = ''<i><span foreground="##${base06}">Password...</span></i>'';
          hide_input = false;
          position = "0, -120";
          halign = "center";
          valign = "center";
        }];

        label = with config.colorScheme.palette; [
          {
            text = ''cmd[update:1000] date +"%H:%M"'';
            color = "rgb(${base05})";
            font_size = 120;
            font_family = "JetBrains Mono Nerd Font Mono ExtraBold";
            position = "0, -300";
            halign = "center";
            valign = "top";
            shadow_passes = 3;
            shadow_size = 8;
          }
        ];
      };
    };
  };
}
