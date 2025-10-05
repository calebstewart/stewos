{...}:
{lib, config, ...}:
let
  cfg = config.stewos.alacritty;
in {
  options.stewos.alacritty.enable = lib.mkEnableOption "alacritty";

  config = lib.mkIf cfg.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        window = {
          opacity = 0.9;
          blur = true;
          dynamic_title = true;
          decorations = "None";
        };

        font = {
          normal.family = "JetBrainsMono Nerd Font Mono";
        };

        colors = with config.colorScheme.palette; {
          transparent_background_colors = true;

          primary = {
            background = "#${base00}";
            foreground = "#${base05}";
          };

          normal = {
            black = "#${base00}";
            red = "#${base08}";
            green = "#${base0B}";
            yellow = "#${base0A}";
            blue = "#${base0D}";
            magenta = "#${base0E}";
            cyan = "#${base0C}";
            white = "#${base05}";
          };
        };
      };
    };
  };
}
