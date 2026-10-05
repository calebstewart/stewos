# Theming, for every surface of the Windows desktop that takes a colour: the
# shell's accent and mode, the wallpaper, the console host's default palette,
# komorebi's borders, YASB's bar and launcher, and komorebi-bar and Flow
# Launcher for a host that turns them back on.
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

  # "1e1e2e" -> "30, 30, 46", for rgba(var(--base00-rgb), 0.4).
  rgb =
    hex:
    lib.concatMapStringsSep ", " (i: toString (lib.fromHexString (builtins.substring i 2 hex))) [
      0
      2
      4
    ];

  # The variables ./yasb.css is written against: each base16 slot, and the
  # same as "r, g, b" for rgba(). YASB substitutes var() itself, as text,
  # before Qt reads the sheet.
  slots = lib.filter (lib.hasPrefix "base") (lib.attrNames palette);
  yasbRoot = ''
    :root {
    ${
      lib.concatMapStrings (slot: ''
        --${slot}: #${palette.${slot}};
        --${slot}-rgb: ${rgb palette.${slot}};
      '') slots
    }}
  '';
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

      programs.yasb.style = lib.mkDefault (yasbRoot + builtins.readFile ./yasb.css);

      programs.komorebi.base16.palette = lib.mkDefault palette;

      programs.flow-launcher.base16 = {
        palette = lib.mkDefault palette;
        name = lib.mkDefault scheme.name;
      };
    }
  );
}
