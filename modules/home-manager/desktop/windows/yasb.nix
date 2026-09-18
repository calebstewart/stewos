# YASB (programs.yasb, ../../yasb.nix): the bar along the top of every
# monitor, and through its Quick Launch widget the launcher the "launcher"
# binding opens. It takes the place of komorebi-bar and Flow Launcher, which
# a host can still turn back on.
#
# The layout is the "Comfyppuccin Reimagined" theme
# (github:amnweb/yasb-themes, 0992d77b-662a-4f6b-ad41-551279d4f716). Its
# stylesheet, recoloured from colorScheme, is ./yasb.css, set in ./theme.nix;
# steward runs YASB (./services.nix), and ./bindings.nix hands Quick Launch its
# hotkey. Where the layout departs from the theme:
# - komorebi's workspaces in place of GlazeWM's, and the tray menu's
#   start/stop/reload commands aimed at komorebi's steward unit.
# - No wallpaper widget: this desktop sets the wallpaper (./theme.nix), and
#   the widget would change it behind the configuration's back.
# - No weather widget: it needs a weatherapi.com key of one's own (the theme
#   ships its author's).
# - No update-check widget.
# - A Quick Launch widget, which the theme does not have.
# - No padding below the bar: komorebi's own workspace padding is the gap
#   between the bar and the windows, as at the screen's other edges.
# - The notes widget's settings sit under `options`. The theme had them one
#   level up, where YASB ignores them, so its menu and icons never applied.
#   Its shadow and padding are dropped rather than moved: YASB 2.x removed
#   both in favour of CSS. So is `blur` on the power menu, likewise gone.
# - Nerd Font glyphs are written literally, as the rest of the repository
#   does; the theme's \u escapes name the same code points.
#
# Every value is mkDefault down to the leaves, so a host changes one setting
# without restating the rest, and a list (a bar's widgets) by giving its own.
{
  options,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  palette = config.colorScheme.palette;
  colour = slot: "#${palette.${slot}}";

  # mkDefault on every leaf of an attribute set, lists included whole.
  mkDefaultDeep =
    value: if lib.isAttrs value then lib.mapAttrs (_: mkDefaultDeep) value else lib.mkDefault value;

  komorebic = verb: "stewctl ${verb} komorebi";

  # A menu popup in the theme's style.
  popup = {
    blur = true;
    round_corners = true;
    round_corners_type = "normal";
  };
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      programs.yasb.enable = lib.mkDefault true;

      # The cava widget draws what cava.exe hands it, and finds it on PATH.
      home.packages = lib.mkIf config.programs.yasb.enable [
        (pkgs.winpkgs.fromWinget {
          id = "karlstav.cava";
          scope = "machine";
        })
      ];

      programs.yasb.settings = mkDefaultDeep {
        watch_stylesheet = true;
        watch_config = true;
        debug = false;
        # winget, through winpkgs, keeps it up to date.
        update_check = false;

        komorebi = {
          start_command = komorebic "start";
          stop_command = komorebic "stop";
          reload_command = komorebic "restart";
        };

        bars.status-bar = {
          enabled = true;
          # "**" is every monitor; "*" would be only those no other bar claims.
          screens = [ "**" ];
          class_name = "yasb-bar";
          alignment.position = "top";
          animation = {
            enabled = true;
            duration = 800;
          };
          blur_effect = {
            enabled = false;
            dark_mode = false;
            round_corners = true;
            border_color = "none";
          };
          window_flags = {
            always_on_top = false;
            windows_app_bar = true;
          };
          dimensions = {
            width = "100%";
            height = 40;
          };
          padding = {
            top = 9;
            left = 9;
            bottom = 0;
            right = 9;
          };
          widgets = {
            left = [
              "home"
              "quick_launch"
              "cpu"
              "memory"
              "traffic"
              "media"
            ];
            center = [
              "komorebi_workspaces"
              "active_window"
            ];
            right = [
              "notes"
              "clock"
              "cava"
              "volume"
              "wifi"
              "disk"
              "power_menu"
            ];
          };
        };

        widgets = {
          # Not in the theme: a Spotlight-style search, and this desktop's
          # launcher. Its hotkey is the "launcher" binding, which
          # ./bindings.nix renders into `options.keybindings` rather than
          # whkd's configuration: yasbc has no command that opens it, so YASB
          # has to hold the key itself.
          quick_launch = {
            type = "yasb.quick_launch.QuickLaunchWidget";
            options = {
              label = "<span></span>";
              search_placeholder = "Search...";
              max_results = 30;
              popup = popup // {
                border_color = colour "base0E";
                dark_mode = true;
              };
              # Only what needs no setup. The rest stay off, including the two
              # YASB turns on by default (snippets and color), and anything
              # that talks to a web service besides web search itself.
              providers =
                let
                  on = [
                    "apps"
                    "calculator"
                    "unit_converter"
                    "settings"
                    "system_commands"
                    "window_switcher"
                    "web_search"
                    "emoji"
                    "kill_process"
                    "wsl"
                  ];
                in
                lib.genAttrs on (lib.const { enabled = true; })
                // {
                  snippets.enabled = false;
                  color.enabled = false;
                };
            };
          };

          # The labels are there for YASB; the stylesheet draws each workspace
          # as a dot and hides the text.
          komorebi_workspaces = {
            type = "komorebi.workspaces.WorkspaceWidget";
            options = {
              label_offline = "komorebi offline";
              hide_if_offline = false;
            };
          };

          cava = {
            type = "yasb.cava.CavaWidget";
            options = {
              bar_height = 12;
              gradient = 1;
              reverse = 0;
              foreground = colour "base0E";
              gradient_color_1 = colour "base0E";
              gradient_color_2 = colour "base07";
              bars_number = 8;
              bar_spacing = 2;
              bar_width = 5;
              sleep_timer = 2;
              hide_empty = false;
            };
          };

          home = {
            type = "yasb.home.HomeWidget";
            options = popup // {
              label = "<span>󰍜</span>";
              menu_list = [
                {
                  title = "Home";
                  path = "~";
                }
                {
                  title = "Downloads";
                  path = "~/Downloads";
                }
                {
                  title = "Documents";
                  path = "~/Documents";
                }
                {
                  title = "Pictures";
                  path = "~/Pictures";
                }
                {
                  title = "Videos";
                  path = "~/Videos";
                }
              ];
              system_menu = true;
              power_menu = false;
              border_color = "";
            };
          };

          media = {
            type = "yasb.media.MediaWidget";
            options = {
              label = "<span>󰎇</span> {title}";
              label_alt = "<span>󰎇</span> {title}";
              hide_empty = true;
              callbacks = {
                on_left = "toggle_media_menu";
                on_middle = "do_nothing";
                on_right = "toggle_label";
              };
              max_field_size = {
                label = 50;
                label_alt = 50;
              };
              show_thumbnail = false;
              controls_only = false;
              controls_left = true;
              thumbnail_alpha = 50;
              thumbnail_padding = 0;
              thumbnail_corner_radius = 8;
              # Segoe Fluent Icons code points, as the menu's buttons are.
              icons = {
                prev_track = "";
                next_track = "";
                play = "";
                pause = "";
              };
              media_menu = popup // {
                border_color = colour "base0E";
                alignment = "right";
                direction = "down";
                offset_top = 6;
                offset_left = 0;
                thumbnail_corner_radius = 8;
                thumbnail_size = 120;
                max_title_size = 80;
                max_artist_size = 20;
                show_source = true;
              };
            };
          };

          clock = {
            type = "yasb.clock.ClockWidget";
            options = {
              label = "<span></span>{%I:%M %p}";
              label_alt = "{%a, %d %b %H:%M:%S}";
              timezones = [ ];
            };
          };

          volume = {
            type = "yasb.volume.VolumeWidget";
            options = {
              label = "<span>{icon}</span> {level}";
              label_alt = "{volume}";
              icons = [
                ""
                ""
                ""
                ""
                ""
              ];
              audio_menu = popup // {
                border_color = colour "base03";
                alignment = "right";
                direction = "down";
              };
              callbacks = {
                on_left = "toggle_volume_menu";
                on_right = "exec cmd.exe /c start ms-settings:sound";
              };
            };
          };

          power_menu = {
            type = "yasb.power_menu.PowerMenuWidget";
            options = {
              label = "";
              uptime = true;
              blur_background = true;
              animation_duration = 250;
              button_row = 3;
              buttons = {
                signout = [
                  "󰍃"
                  "Sign out"
                ];
                shutdown = [
                  ""
                  "Shut Down"
                ];
                restart = [
                  ""
                  "Restart"
                ];
                sleep = [
                  "󰤄"
                  "Sleep"
                ];
                lock = [
                  ""
                  "Lock"
                ];
                cancel = [
                  "󰜺"
                  "Cancel"
                ];
              };
            };
          };

          active_window = {
            type = "yasb.active_window.ActiveWindowWidget";
            options = {
              label = "{win[title]}";
              label_alt = "";
              label_no_window = "";
              label_icon = true;
              label_icon_size = 12;
              max_length = 20;
              max_length_ellipsis = "...";
              monitor_exclusive = true;
            };
          };

          disk = {
            type = "yasb.disk.DiskWidget";
            options = {
              label = "<span></span>";
              label_alt = "<span></span>";
              group_label = popup // {
                volume_labels = [
                  "C"
                  "D"
                  "E"
                  "F"
                ];
                show_label_name = true;
                border_color = "System";
                alignment = "right";
                direction = "down";
              };
              callbacks.on_left = "toggle_group";
            };
          };

          cpu = {
            type = "yasb.cpu.CpuWidget";
            options = {
              label = "<span></span> {info[percent][total]}%";
              label_alt = "<span></span> {info[histograms][cpu_percent]}";
              update_interval = 2000;
              # 0% .. 80%+, a step each tenth.
              histogram_icons = [
                "▁"
                "▁"
                "▂"
                "▃"
                "▄"
                "▅"
                "▆"
                "▇"
                "█"
              ];
              histogram_num_columns = 8;
              callbacks.on_right = "exec cmd /c Taskmgr";
            };
          };

          memory = {
            type = "yasb.memory.MemoryWidget";
            options = {
              label = "<span></span> {virtual_mem_percent}%";
              label_alt = "<span></span> {virtual_mem_used}/{virtual_mem_total}";
              update_interval = 5000;
              callbacks = {
                on_left = "toggle_label";
                on_middle = "do_nothing";
                on_right = "do_nothing";
              };
            };
          };

          wifi = {
            type = "yasb.wifi.WifiWidget";
            options = {
              label = "<span>{wifi_icon}</span>";
              label_alt = "{wifi_name} {wifi_strength}%";
              update_interval = 5000;
              callbacks = {
                on_left = "exec cmd.exe /c start ms-settings:network";
                on_middle = "do_nothing";
                on_right = "toggle_label";
              };
              # 0%, then up to 20, 40, 80 and 100%.
              wifi_icons = [
                "󰤮"
                "󰤟"
                "󰤢"
                "󰤥"
                "󰤨"
              ];
            };
          };

          traffic = {
            type = "yasb.traffic.TrafficWidget";
            options = {
              label = "<span>󰣺</span> {download_speed} {upload_speed}";
              label_alt = "<span>󰣺</span> Download {download_speed} | Upload {upload_speed}";
              update_interval = 1000;
              callbacks = {
                on_left = "toggle_label";
                on_right = "exec cmd /c Taskmgr";
              };
            };
          };

          notes = {
            type = "yasb.notes.NotesWidget";
            options = {
              label = "<span>󰤌</span> {count}";
              label_alt = "{count} notes";
              menu = popup // {
                border_color = "System";
                alignment = "right";
                direction = "down";
                offset_top = 6;
                offset_left = 0;
                show_date_time = true;
              };
              icons = {
                note = "󰤌";
                delete = "";
              };
              callbacks = {
                on_left = "toggle_menu";
                on_middle = "do_nothing";
                on_right = "toggle_label";
              };
            };
          };
        };
      };
    }
  );
}
