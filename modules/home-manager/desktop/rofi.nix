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
        pkgs.stewos.rofi-theme.override {
          colorScheme = config.colorScheme;
        }
      );
    };
  };
}
