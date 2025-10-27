{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.desktop;
  toml = pkgs.formats.toml { };

  switchWorkspacePkg = pkgs.writeShellApplication {
    name = "aerospace-switch-workspace";
    runtimeInputs = with pkgs; [ aerospace ];

    text = ''
      WORKSPACE_INDEX=$1
      WORKSPACES=$(aerospace list-workspaces --monitor focused)
      WORKSPACE_COUNT=$(echo "$WORKSPACES" | wc -l)

      if [[ "$WORKSPACE_INDEX" -ge "1" && "$WORKSPACE_INDEX" -le "$WORKSPACE_COUNT" ]]; then
        aerospace workspace "$(echo "$WORKSPACES" | sed -n "$WORKSPACE_INDEX"'p')"
      fi
    '';
  };

  switchTo =
    workspace: "exec-and-forget ${lib.getExe switchWorkspacePkg} ${builtins.toString workspace}";

  moveToWorkspacePkg = pkgs.writeShellApplication {
    name = "aerospace-move-to-workspace";
    runtimeInputs = with pkgs; [ aerospace ];

    text = ''
      WORKSPACE_INDEX=$1
      WORKSPACES=$(aerospace list-workspaces --monitor focused)
      WORKSPACE_COUNT=$(echo "$WORKSPACES" | wc -l)

      if [[ "$WORKSPACE_INDEX" -ge "1" && "$WORKSPACE_INDEX" -le "$WORKSPACE_COUNT" ]]; then
        aerospace move-node-to-workspace "$(echo "$WORKSPACES" | sed -n "$WORKSPACE_INDEX"'p')"
      fi
    '';
  };

  moveTo =
    workspace: "exec-and-forget ${lib.getExe moveToWorkspacePkg} ${builtins.toString workspace}";
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    home.packages = [ pkgs.aerospace ];

    launchd.agents.aerospace = {
      enable = true;

      config = {
        ProgramArguments = [ "${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };

    xdg.configFile."aerospace/aerospace.toml".source = toml.generate "aerospace.toml" {
      start-at-login = false;
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "horizontal";
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
      automatically-unhide-macos-hidden-apps = true;
      key-mapping.preset = "qwerty";

      gaps.inner = {
        horizontal = 5;
        vertical = 5;
      };

      gaps.outer = {
        left = 0;
        bottom = 0;
        top = 0;
        right = 0;
      };

      # I would love to use `stewos.desktop.bindings` for this, but I don't have the
      # code written yet to translate them into the appropriate configuration.
      mode.main.binding =
        let
          modifier = lib.toLower cfg.modifier;
        in
        {
          "${modifier}-d" = "exec-and-forget open -a \"Raycast\"";
          "${modifier}-enter" = "exec-and-forget open -na \"${lib.getName cfg.terminal}\"";

          "${modifier}-slash" = "layout tiles horizontal vertical";
          "${modifier}-comma" = "layout accordion horizontal vertical";

          "${modifier}-h" = "focus-monitor left";
          "${modifier}-j" = "focus-monitor down";
          "${modifier}-k" = "focus-monitor up";
          "${modifier}-l" = "focus-monitor right";

          "${modifier}-shift-h" = "move-node-to-monitor --focus-follows-window left";
          "${modifier}-shift-j" = "move-node-to-monitor --focus-follows-window down";
          "${modifier}-shift-k" = "move-node-to-monitor --focus-follows-window up";
          "${modifier}-shift-l" = "move-node-to-monitor --focus-follows-window right";

          "${modifier}-minus" = "resize smart -50";
          "${modifier}-equal" = "resize smart +50";

          "${modifier}-1" = switchTo 1;
          "${modifier}-2" = switchTo 2;
          "${modifier}-3" = switchTo 3;
          "${modifier}-4" = switchTo 4;
          "${modifier}-5" = switchTo 5;
          "${modifier}-6" = switchTo 6;
          "${modifier}-7" = switchTo 7;
          "${modifier}-8" = switchTo 8;
          "${modifier}-9" = switchTo 9;
          "${modifier}-0" = switchTo 10;

          "${modifier}-shift-1" = moveTo 1;
          "${modifier}-shift-2" = moveTo 2;
          "${modifier}-shift-3" = moveTo 3;
          "${modifier}-shift-4" = moveTo 4;
          "${modifier}-shift-5" = moveTo 5;
          "${modifier}-shift-6" = moveTo 6;
          "${modifier}-shift-7" = moveTo 7;
          "${modifier}-shift-8" = moveTo 8;
          "${modifier}-shift-9" = moveTo 9;
          "${modifier}-shift-0" = moveTo 10;

          "${modifier}-tab" = "workspace-back-and-forth";
          "${modifier}-shift-tab" = "move-workspace-to-monitor --wrap-around next";

          "${modifier}-shift-semicolon" = "mode service";
        };

      workspace-to-monitor-force-assignment = {
        "1" = "main";
        "2" = "main";
        "3" = "main";
        "4" = "main";
        "5" = "main";
        "6" = [
          "secondary"
          "main"
        ];
        "7" = [
          "secondary"
          "main"
        ];
        "8" = [
          "secondary"
          "main"
        ];
        "9" = [
          "secondary"
          "main"
        ];
        "10" = [
          "secondary"
          "main"
        ];
      };

      mode.service.binding = {
        esc = [
          "reload-config"
          "mode main"
        ];
        r = [
          "flatten-workspace-tree"
          "mode main"
        ];
        f = [
          "layout floating tiling"
          "mode main"
        ];
        backspace = [
          "close-all-windows-but-current"
          "mode main"
        ];
      };
    };
  };
}
