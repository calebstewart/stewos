# How the compositor looks and how it treats particular windows: borders,
# gaps, rounding, blur, animations, and the workspace and window rules.
#
# Colours come from config.colorScheme, the same palette ./theme.nix hands to
# the application toolkits.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.stewos.desktop;
  palette = config.colorScheme.palette;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    wayland.windowManager.hyprland.settings = {
      config = {
        general = {
          gaps_in = 5;
          gaps_out = 1;
          border_size = 1;
          layout = "dwindle";
          allow_tearing = false;

          col = {
            active_border = {
              colors = [
                "rgba(${palette.base0D}ee)"
                "rgba(${palette.base0E}ee)"
              ];
              angle = 45;
            };
            inactive_border = "rgba(${palette.base05}aa)";
          };
        };

        decoration = {
          rounding = 25;

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = "rgba(${palette.base02}ee)";
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

        # The authentication agent prompt: a normal centered floating
        # dialog, pinned so workspace switches don't lose it. The
        # hyprtoolkit rewrite sets a proper app-id, so class matching works.
        {
          match.class = "^hyprpolkitagent$";
          float = true;
          pin = true;
          stay_focused = true;
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
    };
  };
}
