# The compositor itself: what it is started by, which monitors and keyboards it
# drives, and the Lua modules it loads. How it looks is ./style.nix, and what
# the keys do is ./bindings.nix.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.stewos.desktop;

  hyprPkg = config.wayland.windowManager.hyprland.package;

  mkLua = lib.generators.mkLuaInline;

  # Hyprland identifies a monitor by an EDID description prefixed with "desc:".
  # Position and mode are "WxH" strings; "preferred" passes through as-is.
  mkMonitorSpec = mon: {
    output = "desc:${mon.description}";
    mode =
      if lib.isString mon.resolution then
        mon.resolution
      else
        "${toString mon.resolution.width}x${toString mon.resolution.height}";
    position = "${toString mon.position.x}x${toString mon.position.y}";
    scale = mon.scale;
  };

  kbOptions = capsLockEscape: if capsLockEscape then "caps:escape" else "";

  # Hyprland spawns this during compositor init when "startLocked" is set (see
  # "--locked-cmd" below). The session is already force-locked by the time it
  # runs; its job is to hand that force-lock over to the real locker.
  #
  # caelestia's locker lives inside caelestia-shell, which systemd only starts
  # once graphical-session.target is up, so its IPC socket does not exist yet.
  # Poll until it answers instead of racing it: a single early attempt is what
  # made the old ExecStartPost fail roughly half the time.
  caelestiaLockCommand = pkgs.writeShellScript "caelestia-lock-session" ''
    tries=0
    while [ "$tries" -lt 300 ]; do
      if ${lib.getExe config.programs.caelestia.cli.package} shell lock lock >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.2
      tries=$((tries + 1))
    done
    echo "caelestia-shell did not accept the lock IPC within 60s;" \
         "the session is still force-locked with no locker attached" >&2
    exit 1
  '';
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    assertions = [
      {
        assertion = !cfg.startLocked || cfg.lockCommand != null;
        message = "stewos.desktop.startLocked needs a lock command, which the platform backend should have set.";
      }
    ];

    # Hyprland drives the startup lock itself via "--locked-cmd" (see below),
    # so this is not a systemd ExecStartPost. That matters for more than
    # tidiness: Hyprland force-locks at init, and only exempts the incoming
    # ext-session-lock from its "Cannot re-lock" check when it was given a
    # locker command. A lock arriving from anywhere else is denied with a
    # protocol error that kills the shell.
    stewos.desktop.lockCommand = lib.mkDefault "${caelestiaLockCommand}";

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;

      # hyprlang has been deprecated upstream since Hyprland 0.55.
      configType = "lua";

      extraLuaFiles = {
        "hyprsplit/init" = {
          autoLoad = false;
          content = builtins.readFile "${
            inputs.hyprsplit.packages.${pkgs.stdenv.hostPlatform.system}.hyprsplitlua
          }/share/hyprsplit/init.lua";
        };

        # This has to stay autoLoad, even though the "hyprsplit" local below
        # does the real work: home-manager only emits the package.path preamble
        # that require() depends on when at least one extraLuaFile is
        # auto-loaded.
        "stewos-init" = {
          autoLoad = true;
          content = ''
            require("hyprsplit")
          '';
        };
      };

      settings = {
        # Rendered as "local hyprsplit = require(...)" ahead of every other
        # call, so the workspace actions in ./bindings.nix can reference it.
        hyprsplit._var = mkLua ''require("hyprsplit")'';

        monitor = [
          # Fallback for any monitor not described in stewos.desktop.monitors
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = "auto";
          }
        ]
        ++ map mkMonitorSpec cfg.monitors;

        # One call per keyboard that needed settings the session-wide input
        # block does not reach.
        device = lib.mapAttrsToList (
          name: keyboard:
          {
            inherit name;
          }
          // lib.optionalAttrs (keyboard.layout != null) { kb_layout = keyboard.layout; }
          // lib.optionalAttrs (keyboard.variant != null) { kb_variant = keyboard.variant; }
          // lib.optionalAttrs (keyboard.capsLockEscape != null) {
            kb_options = kbOptions keyboard.capsLockEscape;
          }
        ) cfg.keyboards;

        config = {
          misc = {
            # Focus windows that send "activate" requests
            focus_on_activate = true;

            # Disable default images
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
          };

          input = {
            kb_layout = "us";
            kb_options = kbOptions cfg.capsLockEscape;
            follow_mouse = 1;
            sensitivity = 0;
            touchpad.natural_scroll = true;
          };
        };
      };
    };

    # Ensure that the systemd session has access to home-manager session
    # variables. This means that hyprland in turn has access to these variables.
    systemd.user.sessionVariables = config.home.sessionVariables;

    # greetd execs this (see modules/nixos/autologin). Hyprland 0.55+ wants to
    # be started by its watchdog, "start-hyprland": it restarts a crashed
    # compositor in safe mode, and re-locks it if the session was locked when it
    # died. Launching the Hyprland binary directly makes it warn on every boot.
    #
    # "--path" pins the compositor to the same package that generated
    # ~/.config/hypr/hyprland.lua. Home-manager is standalone here, so the
    # system's programs.hyprland package can lag a "nh home switch".
    #
    # Everything after "--" is forwarded to Hyprland. "--locked-cmd" force-locks
    # before the first frame and spawns the locker command.
    #
    # It must be "--locked-cmd" and not the undocumented "--locked": both set
    # the same startLocked state, but only "--locked-cmd" also populates
    # m_startLockedCommand, and CSessionLockManager::onNewSessionLock denies an
    # incoming lock on an already-locked session unless either that string is
    # non-empty or misc:allow_session_lock_restore is set. A denial is a
    # protocol error, so the locker is killed rather than told "no". Hyprland
    # clears m_startLockedCommand once the real locker attaches, which keeps the
    # exemption scoped to this handover instead of leaving re-locking open for
    # the rest of the session the way the config option would.
    #
    # Output is deliberately not redirected, so the watchdog and the compositor
    # both land in "journalctl -u greetd".
    #
    # NOTE: modules/nixos/autologin and the flake templates name this file by
    # its literal path. Renaming it breaks autologin silently.
    home.file.".wayland-session" = {
      executable = true;

      text = ''
        exec ${lib.getExe' hyprPkg "start-hyprland"} --path ${lib.getExe hyprPkg}${lib.optionalString cfg.startLocked " -- --locked-cmd ${cfg.lockCommand}"}
      '';
    };
  };
}
