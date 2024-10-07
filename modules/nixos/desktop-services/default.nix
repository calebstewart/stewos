{lib, config, pkgs, ...}:
let
  cfg = config.stewos.desktop-services;
in {
  options.stewos.desktop-services.enable = lib.mkEnableOption "desktop-services";

  config = lib.mkIf cfg.enable {
    # Most things expect this to be around
    services.gnome.gnome-keyring.enable = true;
    services.dbus.packages = [pkgs.gcr];

    # Configure existence of PAM services
    security.pam.services.hyprlock = {};
    security.pam.services.swaylock = {};
    security.pam.services.gdm = {};

    # Setup OpenGL acceleration support
    hardware.graphics = {
      enable = true;

      extraPackages = with pkgs; [
        vaapiVdpau
        libvdpau-va-gl
      ];
    };

    # Enable Wayland Support across NixOS
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
