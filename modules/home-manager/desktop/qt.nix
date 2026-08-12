{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;

  hyprqt6engine = inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The engine installs its Qt plugins at lib/qt-6/{platformthemes,styles},
  # but home-manager's QT_PLUGIN_PATH points at the profile's
  # lib/qt-6/plugins directory. Re-root them so the profile picks them up.
  hyprqt6enginePlugins = pkgs.runCommand "hyprqt6engine-plugins" { } ''
    mkdir -p $out/${pkgs.qt6.qtbase.qtPluginPrefix}
    ln -s ${hyprqt6engine}/lib/qt-6/platformthemes \
      $out/${pkgs.qt6.qtbase.qtPluginPrefix}/platformthemes
    ln -s ${hyprqt6engine}/lib/qt-6/styles \
      $out/${pkgs.qt6.qtbase.qtPluginPrefix}/styles
  '';
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    qt = {
      enable = true;
      # The Hyprland Qt6 platform theme. Colours, fonts, icons and the widget
      # style for Qt apps come from ~/.config/hypr/hyprqt6engine.conf, which
      # hypr-theme.nix generates. Note this is Qt6-only; Qt5 apps fall back to
      # Qt defaults.
      platformTheme.name = "hyprqt6engine";
    };

    home.packages = [ hyprqt6enginePlugins ];
  };
}
