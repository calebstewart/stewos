{lib, config, pkgs, ...}:
let
  cfg = config.stewos.desktop-services;
in {
  options.stewos.desktop-services.enable = lib.mkEnableOption "desktop-services";

  config = lib.mkIf cfg.enable {
    # Most things expect this to be around
    services.gnome.gnome-keyring.enable = true;
    services.dbus.packages = [pkgs.gcr];

    # Allow hyprlock to unlock the system
    security.pam.services.hyprlock = {};
  };
}
