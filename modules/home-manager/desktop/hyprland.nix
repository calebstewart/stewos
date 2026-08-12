{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.stewos.desktop;

  hypr = inputs.self.lib.hypr;

  hyprPkg = config.wayland.windowManager.hyprland.package;

  # Dispatchers that map a legacy Hyprland dispatcher name onto the Lua API. Each
  # entry takes the binding's "args" (normalized to a single string) and returns a
  # raw Lua expression suitable for the second argument of "hl.bind".
  #
  # "exec" and "rofi" are handled separately because they build their command line
  # from the binding's package/target/args, and "lua" is an escape hatch which
  # takes a raw expression from the binding's "lua" option.
  luaDispatchers = {
    global = args: hypr.mkDispatcher "hl.dsp.global" args;
    movefocus = args: hypr.mkDispatcher "hl.dsp.focus" { direction = args; };
    movewindow = args: hypr.mkDispatcher "hl.dsp.window.move" { direction = args; };
    killactive = _: hypr.mkDispatcher "hl.dsp.window.close" null;
    togglesplit = _: hypr.mkDispatcher "hl.dsp.layout" "togglesplit";
    togglefloating = _: hypr.mkDispatcher "hl.dsp.window.float" { action = "toggle"; };
    fullscreen = _: hypr.mkDispatcher "hl.dsp.window.fullscreen" null;
    pseudo = _: hypr.mkDispatcher "hl.dsp.window.pseudo" null;

    # Provided by the hyprsplit Lua module, bound to the "hyprsplit" local that
    # the settings block below declares via "_var".
    "split:workspace" = args: hypr.mkDispatcher "hyprsplit.dsp.focus" { workspace = args; };
    "split:movetoworkspace" = args: hypr.mkDispatcher "hyprsplit.dsp.window.move" { workspace = args; };
  };

  # Dispatcher names which are handled by generateBinding rather than luaDispatchers.
  builtinDispatchers = [
    "exec"
    "rofi"
    "lua"
  ];

  # Create an exec binding which runs rofi with the given theme, mode, and custom mode list.
  mkRofiBinding =
    {
      modifier,
      key,
      theme ? null,
      modes,
    }:
    let
      # Collect all custom modes into a list of modeName:scriptModePath strings
      customModes = lib.foldl (
        acc: mode:
        acc
        ++ (
          if lib.isDerivation mode then
            [
              "${lib.getName mode}:${lib.getExe mode}"
            ]
          else
            [ ]
        )
      ) [ ] modes;
      customModesArgs =
        if customModes != [ ] then
          [
            "-modes"
            (lib.concatStringsSep "," customModes)
          ]
        else
          [ ];

      # Only pass a "-theme" argument if a theme was provided
      themeArgs =
        if theme != null then
          [
            "-theme"
            theme
          ]
        else
          [ ];

      # Collect all mode names (for custom modes, use lib.getName, otherwise pass through)
      modeNames = lib.forEach modes (mode: if lib.isDerivation mode then (lib.getName mode) else mode);
      modeArgs = [
        "-show"
        (lib.concatStringsSep "," modeNames)
      ];
    in
    hypr.mkExecBinding {
      inherit modifier key;
      package = config.stewos.rofi.package;
      args = modeArgs ++ themeArgs ++ customModesArgs;
    };

  # Generate a single "hl.bind" call wrapped in an array, or an empty
  # array if the given binding config is disabled.
  generateBinding =
    modifier: key: binding:
    let
      # Dispatchers other than "exec" take a single argument string; accept a list
      # for convenience and join it the way hyprlang used to.
      rawArgs = lib.attrByPath [ "args" ] "" binding;
      dispatcherArgs = if lib.isList rawArgs then lib.concatStringsSep " " rawArgs else rawArgs;
    in
    if binding.enable then
      [
        (
          if binding.dispatcher == "exec" then
            hypr.mkExecBinding {
              inherit modifier key;
              inherit (binding) package;
              target = lib.attrByPath [ "target" ] null binding;
              args = lib.attrByPath [ "args" ] [ ] binding;
            }
          else if binding.dispatcher == "rofi" then
            mkRofiBinding {
              inherit modifier key;
              inherit (binding) modes;
              theme = lib.attrByPath [ "theme" ] null binding;
            }
          else
            hypr.mkBinding {
              inherit modifier key;
              dispatcher =
                if binding.dispatcher == "lua" then
                  hypr.mkLua binding.lua
                else
                  luaDispatchers.${binding.dispatcher} dispatcherArgs;
            }
        )
      ]
    else
      [ ];

  # Generate a list of bindings from a binding configuration
  foldlKeys =
    modifier: keys:
    lib.foldlAttrs (
      acc: key: binding:
      acc ++ (generateBinding modifier key binding)
    ) [ ] keys;
  generateBindings =
    bindings:
    lib.foldlAttrs (
      acc: modifier: keys:
      acc ++ (foldlKeys modifier keys)
    ) [ ] bindings;

  # Every dispatcher name referenced by an enabled binding, used to assert that we
  # know how to render it as Lua rather than failing at Hyprland startup.
  usedDispatchers =
    bindings:
    lib.unique (
      lib.foldlAttrs (
        acc: _: keys:
        acc
        ++ lib.foldlAttrs (
          keyAcc: _: binding:
          keyAcc ++ lib.optional binding.enable binding.dispatcher
        ) [ ] keys
      ) [ ] bindings
    );

  unknownDispatchers = lib.filter (
    name: !(builtins.elem name builtinDispatchers) && !(luaDispatchers ? ${name})
  ) (lib.unique ((usedDispatchers defaultBindings) ++ (usedDispatchers cfg.bindings)));

  defaultBindings = {
    "" = {
      "XF86MonBrightnessUp" = {
        enable = true;
        dispatcher = "global";
        args = "caelestia:brightnessUp";
      };
      "XF86MonBrightnessDown" = {
        enable = true;
        dispatcher = "global";
        args = "caelestia:brightnessDown";
      };
      "XF86AudioRaiseVolume" = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.wireplumber;
        target = "wpctl";
        args = [
          "set-volume"
          "-l"
          "1"
          "@DEFAULT_AUDIO_SINK@"
          "5%+"
        ];
      };
      "XF86AudioLowerVolume" = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.wireplumber;
        target = "wpctl";
        args = [
          "set-volume"
          "-l"
          "1"
          "@DEFAULT_AUDIO_SINK@"
          "5%-"
        ];
      };
    };
    "${cfg.modifier}" = {
      "1" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "1";
      };
      "2" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "2";
      };
      "3" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "3";
      };
      "4" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "4";
      };
      "5" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "5";
      };
      "6" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "6";
      };
      "7" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "7";
      };
      "8" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "8";
      };
      "9" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "9";
      };
      "0" = {
        enable = true;
        dispatcher = "split:workspace";
        args = "10";
      };

      H = {
        enable = true;
        dispatcher = "movefocus";
        args = "l";
      };
      J = {
        enable = true;
        dispatcher = "movefocus";
        args = "d";
      };
      K = {
        enable = true;
        dispatcher = "movefocus";
        args = "u";
      };
      L = {
        enable = true;
        dispatcher = "movefocus";
        args = "r";
      };
      Q = {
        enable = true;
        dispatcher = "killactive";
      };
      D = {
        enable = true;
        dispatcher = "global";
        args = "caelestia:launcher";
      };
      V = {
        enable = true;
        dispatcher = "togglesplit";
      };
      U = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.stewos.wl-gen-uuid;
      };
      M = {
        enable = true;
        dispatcher = "rofi";
        modes = [ pkgs.stewos.rofi-libvirt ];
      };

      Return = {
        enable = true;
        dispatcher = "exec";
        package = cfg.terminal;
      };

      Backspace = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.systemd;
        target = "loginctl";
        args = [ "lock-session" ];
      };
    };

    "${cfg.modifier} SHIFT" = {
      "1" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "1";
      };
      "2" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "2";
      };
      "3" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "3";
      };
      "4" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "4";
      };
      "5" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "5";
      };
      "6" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "6";
      };
      "7" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "7";
      };
      "8" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "8";
      };
      "9" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "9";
      };
      "0" = {
        enable = true;
        dispatcher = "split:movetoworkspace";
        args = "10";
      };

      H = {
        enable = true;
        dispatcher = "movewindow";
        args = "l";
      };
      J = {
        enable = true;
        dispatcher = "movewindow";
        args = "d";
      };
      K = {
        enable = true;
        dispatcher = "movewindow";
        args = "u";
      };
      L = {
        enable = true;
        dispatcher = "movewindow";
        args = "r";
      };
      E = {
        enable = true;
        dispatcher = "rofi";
        modes = [ pkgs.stewos.rofi-hyprpower ];
      };
      R = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.grimblast;
        args = [
          "copy"
          "area"
          "--notify"
        ];
      };
      P = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.grimblast;
        args = [
          "copy"
          "output"
          "--notify"
        ];
      };
      F = {
        enable = true;
        dispatcher = "fullscreen";
      };

      Space = {
        enable = true;
        dispatcher = "togglefloating";
      };
    };
  };
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    assertions = [
      {
        assertion = unknownDispatchers == [ ];
        message = "stewos.desktop.bindings uses Hyprland dispatchers with no Lua mapping: ${lib.concatStringsSep ", " unknownDispatchers}. Add them to luaDispatchers in modules/home-manager/desktop/hyprland.nix, or use dispatcher = \"lua\" with a raw expression.";
      }
    ];

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

        # This has to stay autoLoad, even though the "hyprsplit" local below does
        # the real work: home-manager only emits the package.path preamble that
        # require() depends on when at least one extraLuaFile is auto-loaded.
        "stewos-init" = {
          autoLoad = true;
          content = ''
            require("hyprsplit")
          '';
        };
      };

      settings = {
        # Rendered as "local hyprsplit = require(...)" ahead of every other call,
        # so the split:* bindings below can reference it.
        hyprsplit._var = hypr.mkLua ''require("hyprsplit")'';

        monitor = [
          # Fallback for any monitor not described in stewos.desktop.monitors
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = "auto";
          }
        ]
        ++ map hypr.mkMonitorSpec cfg.monitors;

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
            kb_options = if cfg.swapEscape then "caps:swapescape" else "";
            follow_mouse = 1;
            sensitivity = 0;
            touchpad.natural_scroll = true;
          };

          general = with config.colorScheme.palette; {
            gaps_in = 5;
            gaps_out = 1;
            border_size = 1;
            layout = "dwindle";
            allow_tearing = false;

            col = {
              active_border = {
                colors = [
                  "rgba(${base0D}ee)"
                  "rgba(${base0E}ee)"
                ];
                angle = 45;
              };
              inactive_border = "rgba(${base05}aa)";
            };
          };

          decoration = {
            rounding = 25;

            shadow = {
              enabled = true;
              range = 4;
              render_power = 3;
              color = "rgba(${config.colorScheme.palette.base02}ee)";
            };

            blur = {
              enabled = true;
              size = 8;
              passes = 1;
            };
          };

          animations.enabled = true;

          # NOTE: "pseudotile" was removed upstream; pseudotiling is now the
          # "pseudo" window rule effect / hl.dsp.window.pseudo() dispatcher.
          dwindle.preserve_split = true;
        };

        # "curve" is one of home-manager's importantPrefixes, so this is always
        # emitted ahead of the animations which reference it.
        curve = {
          _args = [
            "myBezier"
            {
              type = "bezier";
              points = [
                [
                  0.05
                  0.9
                ]
                [
                  0.1
                  1.05
                ]
              ];
            }
          ];
        };

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 7;
            bezier = "myBezier";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 7;
            bezier = "default";
            style = "popin 80%";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 10;
            bezier = "default";
          }
          {
            leaf = "borderangle";
            enabled = true;
            speed = 8;
            bezier = "default";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 7;
            bezier = "default";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 6;
            bezier = "default";
          }
        ];

        # Smart gaps
        workspace_rule = [
          {
            workspace = "w[t1]";
            gaps_out = 0;
            gaps_in = 0;
          }
          {
            workspace = "w[tg1]";
            gaps_out = 0;
            gaps_in = 0;
          }
          {
            workspace = "f[1]";
            gaps_out = 0;
            gaps_in = 0;
          }
        ];

        # NOTE: rules are evaluated top to bottom and the last match wins, so the
        # order here is significant. They are deliberately left anonymous; naming a
        # rule would promote it ahead of every anonymous one.
        window_rule = [
          # Disallow maximization, and inhibit idle when fullscreen
          {
            match.class = ".*";
            suppress_event = "maximize";
            idle_inhibit = "fullscreen";
          }

          {
            match.class = "showmethekey-gtk";
            float = true;
            size = [
              "monitor_w"
              "monitor_h*0.1"
            ];
            move = [
              "0"
              "monitor_h*0.9"
            ];
            # Window rules have no "no_border"; that is a workspace rule field.
            border_size = 0;
            animation = "slide bottom";
          }

          # Smart Gaps
          {
            match = {
              float = false;
              workspace = "w[t1]";
            };
            border_size = 0;
          }
          {
            match = {
              float = false;
              workspace = "w[tg1]";
            };
            border_size = 0;
          }
          {
            match = {
              float = false;
              workspace = "f[1]";
            };
            border_size = 0;
          }

          # Make the authentication agent prompt *special* o.O
          {
            match.class = "polkit-gnome-authentication-agent-1";
            float = true;
            move = [
              "monitor_w*0.37"
              "monitor_h*0.02"
            ];
            size = [
              "monitor_w*0.25"
              "monitor_h*0.1"
            ];
            pin = true;
            stay_focused = true;
            animation = "slide top";
            workspace = "special:polkit";
          }

          # Float windows with a dash prefix in their class like a dashboard
          {
            match.class = "^dash";
            float = true;
            move = [
              "monitor_w*0.33"
              "monitor_h*0.02"
            ];
            size = [
              "monitor_w*0.33"
              "monitor_h*0.25"
            ];
            opacity = "0.98";
            stay_focused = true;
            animation = "slide top";
          }

          # Make slack into a floating drop-down panel
          {
            match.class = "^Slack$";
            float = true;
            move = [
              "monitor_w*0.15"
              "monitor_h*0.02"
            ];
            size = [
              "monitor_w*0.7"
              "monitor_h*0.75"
            ];
            animation = "slide top";
            workspace = "special:slack";
          }

          {
            match.class = "^dash:shell$";
            workspace = "special:shell";
          }
          {
            match.class = "^dash:python$";
            workspace = "special:python";
          }
        ];

        # Generate all the bindings
        bind = lib.mkMerge [
          (generateBindings defaultBindings)
          (generateBindings cfg.bindings)
        ];
      };
    };

    # Ensure that the systemd session has access to home-manager session variables.
    # This means that hyprland in turn has access to these variables.
    systemd.user.sessionVariables = config.home.sessionVariables;

    # greetd execs this (see modules/nixos/autologin). Hyprland 0.55+ wants to be
    # started by its watchdog, "start-hyprland": it restarts a crashed compositor
    # in safe mode, and re-locks it if the session was locked when it died.
    # Launching the Hyprland binary directly makes it warn on every boot.
    #
    # "--path" pins the compositor to the same package that generated
    # ~/.config/hypr/hyprland.lua. Home-manager is standalone here, so the
    # system's programs.hyprland package can lag a "nh home switch".
    #
    # Everything after "--" is forwarded to Hyprland. "--locked-cmd" force-locks
    # before the first frame and spawns the locker command (see
    # stewos.desktop.lockCommand in default.nix).
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
    home.file.".wayland-session" = {
      executable = true;

      text = ''
        exec ${lib.getExe' hyprPkg "start-hyprland"} --path ${lib.getExe hyprPkg}${lib.optionalString cfg.startLocked " -- --locked-cmd ${cfg.lockCommand}"}
      '';
    };
  };
}
