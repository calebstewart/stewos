{lib, config, pkgs, ...}:
let
  cfg = config.stewos.desktop;
  toml = pkgs.formats.toml {};
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    home.packages = [pkgs.aerospace];

    launchd.agents.aerospace = {
      enable = true;

      config = {
        ProgramArguments = ["${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"];
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
      on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
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
      mode.main.binding = let
        modifier = lib.toLower cfg.modifier;
      in {
        "${modifier}-d" = "exec-and-forget open -a \"Raycast\"";
        "${modifier}-enter" = "exec-and-forget open -na \"${lib.getName cfg.terminal}\"";

        "${modifier}-slash" = "layout tiles horizontal vertical";
        "${modifier}-comma" = "layout accordion horizontal vertical";

        "${modifier}-h" = "focus left";
        "${modifier}-j" = "focus down";
        "${modifier}-k" = "focus up";
        "${modifier}-l" = "focus right";

        "${modifier}-shift-h" = "move left";
        "${modifier}-shift-j" = "move down";
        "${modifier}-shift-k" = "move up";
        "${modifier}-shift-l" = "move right";

        "${modifier}-minus" = "resize smart -50";
        "${modifier}-equal" = "resize smart +50";

        "${modifier}-1" = "workspace 1";
        "${modifier}-2" = "workspace 2";
        "${modifier}-3" = "workspace 3";
        "${modifier}-4" = "workspace 4";
        "${modifier}-5" = "workspace 5";
        "${modifier}-6" = "workspace 6";
        "${modifier}-7" = "workspace 7";
        "${modifier}-8" = "workspace 8";
        "${modifier}-9" = "workspace 9";
        "${modifier}-0" = "workspace 10";

        "${modifier}-shift-1" = "move-node-to-workspace 1";
        "${modifier}-shift-2" = "move-node-to-workspace 2";
        "${modifier}-shift-3" = "move-node-to-workspace 3";
        "${modifier}-shift-4" = "move-node-to-workspace 4";
        "${modifier}-shift-5" = "move-node-to-workspace 5";
        "${modifier}-shift-6" = "move-node-to-workspace 6";
        "${modifier}-shift-7" = "move-node-to-workspace 7";
        "${modifier}-shift-8" = "move-node-to-workspace 8";
        "${modifier}-shift-9" = "move-node-to-workspace 9";
        "${modifier}-shift-0" = "move-node-to-workspace 10";

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
        "6" = ["secondary" "main"];
        "7" = ["secondary" "main"];
        "8" = ["secondary" "main"];
        "9" = ["secondary" "main"];
        "10" = ["secondary" "main"];
      };

      mode.service.binding = {
        esc = ["reload-config" "mode main"];
        r = ["flatten-workspace-tree" "mode main"];
        f = ["layout floating tiling" "mode main"];
        backspace = ["close-all-windows-but-current" "mode main"];
      };
    };
  };
}

