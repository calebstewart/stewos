{ lib, config, ... }:
let
  cfg = config.stewos.alacritty;
in
{
  options.stewos.alacritty.enable = lib.mkEnableOption "alacritty";

  config = lib.mkIf cfg.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        window = {
          opacity = lib.mkDefault 0.9;
          blur = lib.mkDefault true;
          dynamic_title = lib.mkDefault true;
          decorations = lib.mkDefault "none";

          padding.x = lib.mkDefault 10;
          padding.y = lib.mkDefault 10;
        };

        font = {
          normal.family = lib.mkDefault "JetBrainsMono Nerd Font Mono";
        };

        colors = lib.mkDefault (with config.colorScheme.palette; {
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
        });
      };
    };
  };
}
