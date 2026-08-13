{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.desktop-services;
in
{
  options.stewos.desktop-services.enable = lib.mkEnableOption "desktop-services";

  config = lib.mkIf cfg.enable {
    # Most things expect this to be around
    services.gnome.gnome-keyring.enable = true;
    services.dbus.packages = [ pkgs.gcr ];

    # PAM does not start the keyring's *secrets* component. Its auto_start brings
    # up "gnome-keyring-daemon --login", which owns no well-known bus name; the
    # secrets component only appears once something asks for
    # org.freedesktop.secrets and D-Bus activates gnome-keyring again, at which
    # point the second process finds the first ("discover_other_daemon"), hands
    # the work over and -- because the activation file passes --foreground --
    # sits there parked for the rest of the session.
    #
    # That bootstrap is demand-driven, which loses a race we care about. The
    # locker unlocks the login keyring through pam_gnome_keyring (see
    # pkgs/caelestia-shell), and with autologin plus a session that comes up
    # locked, the first unlock happens before anything has asked for a secret.
    # The unlock then reaches a daemon that cannot service it and is reported as
    # "the password for the login keyring was invalid", which looks exactly like
    # a wrong password. Observed at boot: daemon at 19:35:44, failed unlock at
    # 19:35:52, secrets component activated at 19:36:00.
    #
    # Starting the component up front removes the race, and since the bus name is
    # then already owned, the D-Bus activation never fires and the parked stub
    # never appears either.
    #
    # "--start" hands off to the daemon PAM already started and exits 0, hence
    # oneshot; the setuid wrapper is what the activation files invoke as well.
    systemd.user.services.gnome-keyring-secrets = {
      description = "Start the gnome-keyring secrets component";
      wantedBy = [ "graphical-session-pre.target" ];
      before = [ "graphical-session.target" ];
      after = [ "dbus.socket" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/wrappers/bin/gnome-keyring-daemon --start --components=secrets";
      };
    };

    # Configure existence of PAM services
    security.pam.services.hyprlock = { };
    security.pam.services.swaylock = { };
    security.pam.services.gdm = { };

    # Setup OpenGL acceleration support
    hardware.graphics = {
      enable = true;

      extraPackages = with pkgs; [
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    # Enable Wayland Support across NixOS
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
