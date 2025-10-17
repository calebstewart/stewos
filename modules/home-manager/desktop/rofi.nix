{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    stewos.rofi = {
      enable = true;
      theme = lib.mkDefault (
        pkgs.rofiThemes.stewos.override {
          colorScheme = config.colorScheme;
        }
      );
    };
  };
}
