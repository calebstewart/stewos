{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.ghostty;
in
{
  options.stewos.ghostty.enable = lib.mkEnableOption "ghostty";

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;

      # The source `ghostty` package is Linux-only in nixpkgs; the official
      # binary distribution supports darwin.
      package = pkgs.ghostty-bin;

      settings = {
        font-family = "JetBrainsMono Nerd Font Mono";

        background-opacity = 0.9;
        background-blur = true;

        window-padding-x = 10;
        window-padding-y = 10;
        window-decoration = false;

        background = "#${config.colorScheme.palette.base00}";
        foreground = "#${config.colorScheme.palette.base05}";

        palette = with config.colorScheme.palette; [
          "0=#${base00}"
          "1=#${base08}"
          "2=#${base0B}"
          "3=#${base0A}"
          "4=#${base0D}"
          "5=#${base0E}"
          "6=#${base0C}"
          "7=#${base05}"
        ];
      };
    };
  };
}
