# The Linux desktop: Hyprland, plus the shell and session services around it.
#
# Every file here guards its own config on "cfg.enable && isLinux" rather than
# being imported conditionally, because deciding what to import from
# pkgs.stdenv risks a recursion the module system cannot see through.
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  imports = [
    inputs.caelestia-shell.homeManagerModules.default

    ./hyprland.nix
    ./style.nix
    ./bindings.nix
    ./theme.nix
    ./polkit.nix
    ./xdg.nix
  ];

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    # caelestia owns the pieces a Hyprland setup would otherwise wire up one at
    # a time: the locker, idle handling, notifications, the bar and the
    # wallpaper daemon.
    programs.caelestia = {
      enable = true;
      systemd.enable = true;
      cli.enable = true;

      settings = {
        paths.wallpaperDir = "~/Pictures/Wallpapers";

        # Defaults to IP location
        services.weatherLocation = lib.mkDefault "";

        # We run a single-user system, so logging out is just locking the screen.
        session.commands.logout = [
          "loginctl"
          "lock-session"
        ];
      };
    };

    # Setup a volume control application
    home.packages = [ pkgs.pwvucontrol ];

    # Electron reads this natively to pick its Ozone backend, which is the
    # supported replacement for per-package "commandLineArgs" overrides. The
    # Hyprland module copies home.sessionVariables into the systemd user
    # environment, so the whole graphical session inherits it.
    home.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };
  };
}
