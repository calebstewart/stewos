{pkgs, config, lib, stewos, ...}:
let
  cfg = config.stewos.desktop;

  # Create an exec binding which runs rofi with the given theme, mode, and custom mode list.
  mkRofiBinding = {modifier, key, theme ? null, modes}:
  let
    # Collect all custom modes into a list of modeName:scriptModePath strings
    customModes = lib.foldl (acc: mode: acc ++ (if lib.isDerivation mode then [
      "${lib.getName mode}:${lib.getExe mode}"
    ] else [])) [] modes;
    customModesArgs = if customModes != [] then [
      "-modes" (lib.concatStringsSep "," customModes)
    ] else [];

    # Only pass a "-theme" argument if a theme was provided
    themeArgs = if theme != null then ["-theme" theme] else [];

    # Collect all mode names (for custom modes, use lib.getName, otherwise pass through)
    modeNames = lib.forEach modes (mode: if lib.isDerivation mode then (lib.getName mode) else mode);
    modeArgs = ["-show" (lib.concatStringsSep "," modeNames)];
  in stewos.lib.hypr.mkExecBinding {
    inherit modifier key;
    package = config.stewos.rofi.package;
    args = modeArgs ++ themeArgs ++ customModesArgs;
  };

  # Generate a single binding string wrapped in an array or an empty
  # array if the given binding config is disabled.
  generateBinding = modifier: key: binding: if binding.enable then [(
    if binding.dispatcher == "exec" then stewos.lib.hypr.mkExecBinding {
      inherit modifier key;
      inherit (binding) package;
      target = lib.attrByPath ["target"] null binding;
      args = lib.attrByPath ["args"] [] binding;
    } else if binding.dispatcher == "rofi" then mkRofiBinding {
      inherit modifier key;
      inherit (binding) modes;
      theme = lib.attrByPath  ["theme"] null binding;
    } else stewos.lib.hypr.mkBinding {
      inherit modifier key;
      inherit (binding) dispatcher;
      args = lib.attrByPath ["args"] "" binding;
    }
  )] else [];

  # Generate a list of bindings from a binding configuration
  foldlKeys = modifier: keys: lib.foldlAttrs (acc: key: binding: acc ++ (generateBinding modifier key binding)) [] keys;
  generateBindings = bindings: lib.foldlAttrs (acc: modifier: keys: acc ++ (foldlKeys modifier keys)) [] bindings;

  defaultBindings = {
    "${cfg.modifier}" = {
      "1" = { enable = true; dispatcher = "split:workspace"; args = "1"; };
      "2" = { enable = true; dispatcher = "split:workspace"; args = "2"; };
      "3" = { enable = true; dispatcher = "split:workspace"; args = "3"; };
      "4" = { enable = true; dispatcher = "split:workspace"; args = "4"; };
      "5" = { enable = true; dispatcher = "split:workspace"; args = "5"; };
      "6" = { enable = true; dispatcher = "split:workspace"; args = "6"; };
      "7" = { enable = true; dispatcher = "split:workspace"; args = "7"; };
      "8" = { enable = true; dispatcher = "split:workspace"; args = "8"; };
      "9" = { enable = true; dispatcher = "split:workspace"; args = "9"; };
      "0" = { enable = true; dispatcher = "split:workspace"; args = "10"; };

      H = { enable = true; dispatcher = "movefocus"; args = "l"; };
      J = { enable = true; dispatcher = "movefocus"; args = "d"; };
      K = { enable = true; dispatcher = "movefocus"; args = "u"; };
      L = { enable = true; dispatcher = "movefocus"; args = "r"; };
      Q = { enable = true; dispatcher = "killactive"; };
      D = { enable = true; dispatcher = "rofi"; modes = ["drun"]; };
      V = { enable = true; dispatcher = "togglesplit"; };
      U = { enable = true; dispatcher = "exec"; package = pkgs.wl-gen-uuid; };
      M = { enable = true; dispatcher = "rofi"; modes = [pkgs.rofiScripts.libvirt]; };

      N = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.swaynotificationcenter;
        target = "swaync-client";
        args = ["-t" "-sw"];
      };
      
      Return = { enable = true; dispatcher = "exec"; package = cfg.terminal; };

      Backspace = {
        enable = true;
        dispatcher = "exec";
        package = pkgs.systemd;
        target = "loginctl";
        args = ["lock-session"];
      };
    };

    "${cfg.modifier} SHIFT" = {
      "1" = { enable = true; dispatcher = "split:movetoworkspace"; args = "1"; };
      "2" = { enable = true; dispatcher = "split:movetoworkspace"; args = "2"; };
      "3" = { enable = true; dispatcher = "split:movetoworkspace"; args = "3"; };
      "4" = { enable = true; dispatcher = "split:movetoworkspace"; args = "4"; };
      "5" = { enable = true; dispatcher = "split:movetoworkspace"; args = "5"; };
      "6" = { enable = true; dispatcher = "split:movetoworkspace"; args = "6"; };
      "7" = { enable = true; dispatcher = "split:movetoworkspace"; args = "7"; };
      "8" = { enable = true; dispatcher = "split:movetoworkspace"; args = "8"; };
      "9" = { enable = true; dispatcher = "split:movetoworkspace"; args = "9"; };
      "0" = { enable = true; dispatcher = "split:movetoworkspace"; args = "10"; };

      H = { enable = true; dispatcher = "movewindow"; args = "l"; };
      J = { enable = true; dispatcher = "movewindow"; args = "d"; };
      K = { enable = true; dispatcher = "movewindow"; args = "u"; };
      L = { enable = true; dispatcher = "movewindow"; args = "r"; };
      E = { enable = true; dispatcher = "rofi"; modes = [pkgs.rofiScripts.hyprpower]; };
      R = { enable = true; dispatcher = "exec"; package = pkgs.grimblast; args = ["copy" "area" "--notify"]; };
      P = { enable = true; dispatcher = "exec"; package = pkgs.grimblast; args = ["copy" "output" "--notify"]; };
      F = { enable = true; dispatcher = "fullscreen"; };
      
      Space = { enable = true; dispatcher = "togglefloating"; };
    };
  };
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;
      # plugins = with pkgs.hyprlandPlugins; [hyprsplit];

      settings = {
        monitor = lib.lists.foldl (acc: monitor: acc ++ [(stewos.lib.mkMonitorConfig monitor)]) [",preferred,auto,1"] cfg.monitors;

        # Disable default images
        misc = {
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
          gaps_out = 5;
          border_size = 1;
          "col.active_border" = "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
          "col.inactive_border" = "rgba(${base05}aa)";
          layout = "dwindle";
          allow_tearing = false;
        };

        decoration = {
          rounding = 2;

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = "rgba(${config.colorScheme.palette.base02}ee)";
          };

          blur = {
            enabled = true;
            size = 3;
            passes = 1;
          };
        };

        animations = {
          enabled = true;

          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
            "layers, 1, 7, default, slide"
            "specialWorkspace, 1, 6, default, slidefadevert -20%"
          ];
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
          # no_gaps_when_only = 1;
        };

        windowrulev2 = [
          # Disallow maximization, and inhibit idle when fullscreen
          "suppressevent maximize, class:.*"
          "idleinhibit fullscreen, class:.*"

          "float,class:(showmethekey-gtk)"
          "size 100% 10%,class:(showmethekey-gtk)"
          "move 0% 90%,class:(showmethekey-gtk)"
          "noborder,class:(showmethekey-gtk)"
          "animation slide bottom,class:(showmethekey-gtk)"

          # Make the authentication agent prompt *special* o.O
          "float,class:(polkit-gnome-authentication-agent-1)"
          "move 37% 2%,class:(polkit-gnome-authentication-agent)"
          "size 25% 10%,class:(polkit-gnome-authentication-agent)"
          "pin,class:(polkit-gnome-authentication-agent-1)"
          "stayfocused,class:(polkit-gnome-authentication-agent-1)"
          "animation slide top,class:(polkit-gnome-authentication-agent-1)"
          "workspace special:polkit,class:(polkit-gnome-authentication-agent)"

          # Float windows with a dash prefix in their class like a dashboard
          "float,class:^(dash)"
          "move 33% 2%,class:^(dash)"
          "size 33% 25%,class:^(dash)"
          "opacity 0.98,class:^(dash)"
          "stayfocused,class:^(dash)"
          "animation slide top,class:^(dash)"

          # Make slack into a floating drop-down panel
          "float,class:^(Slack)$"
          "move 15% 2%,class:^(Slack)$"
          "size 70% 75%,class:^(Slack)$"
          "animation slide top,class:^(Slack)$"
          "workspace special:slack,class:^(Slack)$"

          "workspace special:shell,class:^(dash:shell)$"
          "workspace special:python,class:^(dash:python)$"
        ];

        # Generate all the bindings
        bind = lib.mkMerge [
          (generateBindings defaultBindings)
          (generateBindings cfg.bindings)
        ];

        source = "${config.xdg.configHome}/hypr/config.d/*.conf";
      };
    };

    # Create an empty file so the glob import doesn't fail
    xdg.configFile."hypr/config.d/00-empty.conf".text = "";

    # Ensure that the systemd session has access to home-manager session variables.
    # This means that hyprland in turn has access to these variables.
    systemd.user.sessionVariables = config.home.sessionVariables;
  };
}
