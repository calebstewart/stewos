{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    xdg.portal = {
      enable = true;

      configPackages = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];

      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };
  };
}
