# Theming, for every surface of the Windows desktop that takes a colour: the
# shell's accent and mode, the wallpaper, the console host's default palette,
# komorebi's borders and bar, and the launcher.
#
# All of it is driven from config.colorScheme, as ../linux/theme.nix is, so
# changing the scheme changes the whole desktop rather than half of it. Every
# value is mkDefault, so a host can still say otherwise about any one of them.
{
  options,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  scheme = config.colorScheme;
  palette = scheme.palette;
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      windows.theme =
        lib.mapAttrs (_: lib.mkDefault) {
          mode = scheme.variant or "dark";
          accentColor = "#${palette.base0D}";
          accentColorInactive = "#${palette.base02}";
          background = "#${palette.base00}";
          accentOnStartAndTaskbar = true;
          accentOnTitleBars = true;
        }
        // {
          wallpaper.image = lib.mkDefault cfg.wallpaper;
        };

      # The default palette of every console window conhost draws.
      windows.console.base16 = lib.mkDefault palette;

      programs.komorebi.base16.palette = lib.mkDefault palette;

      programs.flow-launcher.base16 = {
        palette = lib.mkDefault palette;
        name = lib.mkDefault scheme.name;
      };
    }
  );
}
