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
    # The `_file` is load-bearing for the option documentation. The upstream
    # module is a function, so it carries no position of its own and everything
    # it declares -- `programs.caelestia.*` -- would be attributed to this file
    # and rendered as StewOS's own, with its package defaults showing as opaque
    # `<derivation caelestia-shell-1.0.0>`. Naming the real file keeps upstream's
    # options in upstream's documentation.
    {
      _file = "${inputs.caelestia-shell}/nix/hm-module.nix";
      imports = [ inputs.caelestia-shell.homeManagerModules.default ];
    }

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

      # Our build of the shell, which adds pam_gnome_keyring to the locker's PAM
      # stack so unlocking the screen also unlocks the login keyring. Autologin
      # means the lock screen is the only place a password is entered.
      package = pkgs.stewos.caelestia-shell;

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

    # Restarting the shell must not take down what the shell launched.
    #
    # caelestia launches apps with Quickshell.execDetached, which forks but does
    # not move the child out of caelestia.service's cgroup -- Quickshell has no
    # systemd integration at all. Chromium then rescues *itself*: it calls
    # StartTransientUnit to move its own PID into `app-com.google.Chrome-<pid>.
    # scope`. Only its own PID. The crashpad handler and zygote are forked
    # before that, so they stay behind, and every renderer, GPU and utility
    # process the zygote later forks inherits the cgroup with them. The result
    # is a browser process alone in a scope while its whole process tree sits in
    # caelestia.service.
    #
    # With systemd's default KillMode=control-group, stopping the unit SIGTERMs
    # that whole cgroup. Chromium survives losing a renderer, but not losing the
    # GPU process and zygote at once: it takes SIGTRAP from its own fatal check
    # and dumps core, which is why Chrome and Discord die on every shell restart
    # and reopen with "didn't shut down correctly".
    #
    # KillMode=process kills only quickshell itself. The shell's genuine helpers
    # (an nmcli monitor and a couple of `cat`s on pipes) get EOF or SIGPIPE when
    # it goes and exit on their own, so nothing is leaked by not killing them.
    #
    # This is not a stale pin -- we track upstream main, and main does this.
    # Until caelestia 3d97d50 ("feat: support non-systemd systems", PR #1607,
    # 2026-06-23) the launcher went through app2unit, which starts each app in
    # its own systemd scope and makes this structurally impossible. That commit
    # dropped it deliberately, to run on distros without systemd: app2unit is
    # systemd-only. The tradeoff was not discussed on the PR, and nothing
    # replaced the scope placement it was providing.
    #
    # So this is upstream behaviour we are compensating for locally, not a bug
    # to fix by moving the input. If upstream reintroduces per-app scopes, this
    # override can go.
    systemd.user.services.caelestia.Service.KillMode = "process";

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
