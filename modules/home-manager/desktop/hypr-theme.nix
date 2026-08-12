# Theming for the Hypr ecosystem's three app generations:
#  - application-style.conf: the org.hyprland.style QML style used by the
#    Qt/QML hypr apps (today: hyprpolkitagent's auth dialog).
#  - hyprtoolkit.conf: hyprtoolkit-native apps.
#  - hyprqt6engine.conf: every other Qt6 app, through the hyprqt6engine
#    platform theme enabled in qt.nix.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  palette = config.colorScheme.palette;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    programs.hyprland-qt-support = {
      enable = true;
      settings = {
        roundness = 1;
        border_width = 1;
        reduce_motion = false;
      };
    };

    # All options are top-level (no category blocks); colours are 0xAARRGGBB.
    # Sizes and rounding keep the toolkit defaults.
    xdg.configFile."hypr/hyprtoolkit.conf".text = ''
      background = 0xFF${palette.base01}
      base = 0xFF${palette.base00}
      alternate_base = 0xFF${palette.base02}
      text = 0xFF${palette.base05}
      bright_text = 0xFF${palette.base06}
      accent = 0xFF${palette.base0D}
      accent_secondary = 0xFF${palette.base0C}

      font_family = Roboto
      font_family_monospace = JetBrains Mono
      icon_theme = Papirus
    '';

    # The colour scheme is a qt6ct-format palette file. This one is fixed to
    # Catppuccin Mocha (blue accent) rather than derived from
    # config.colorScheme, matching gtk.nix which hardcodes the same theme.
    # "hyprqt6engine" is the engine's own proxy widget style.
    xdg.configFile."hypr/hyprqt6engine.conf".text = ''
      theme {
        color_scheme = ${pkgs.catppuccin-qt5ct}/share/qt5ct/colors/catppuccin-mocha-blue.conf
        icon_theme = Papirus
        style = hyprqt6engine
        font = Roboto
        font_size = 11
        font_fixed = JetBrains Mono
        font_fixed_size = 11
      }
    '';
  };
}
