# Aerospace, the tiling window manager for macOS.
#
# The neutral binding vocabulary declared in ../options.nix arrives here as
# data. This file owns three tables -- modifiers, keys, and actions -- that say
# what each neutral name means to Aerospace, plus the default keymap, which is
# contributed back into "stewos.desktop.bindings" so a host can override any of
# it by name.
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.desktop;
  toml = pkgs.formats.toml { };

  inherit (inputs.self.lib.desktop) mkCommandLine;

  exec = argv: "exec-and-forget ${lib.escapeShellArgs argv}";

  # Aerospace numbers workspaces per monitor and addresses them by name, so
  # "go to the third one on this display" needs a lookup at runtime rather than
  # a name baked into the config.
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

  # Modifiers are emitted in this order regardless of how they were written, so
  # that two spellings of the same combination render identically.
  modifierOrder = [
    "super"
    "ctrl"
    "alt"
    "shift"
  ];

  aeroModifiers = {
    super = "cmd";
    ctrl = "ctrl";
    alt = "alt";
    shift = "shift";
  };

  # No media keys here: macOS handles brightness and volume in hardware, below
  # anything Aerospace could bind.
  aeroKeys =
    lib.genAttrs (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") lib.id
    // lib.genAttrs (map toString (lib.range 0 9)) lib.id
    // lib.genAttrs (map (n: "f${toString n}") (lib.range 1 12)) lib.id
    // {
      enter = "enter";
      space = "space";
      tab = "tab";
      escape = "esc";
      backspace = "backspace";
      delete = "delete";

      left = "left";
      right = "right";
      up = "up";
      down = "down";

      minus = "minus";
      equal = "equal";
      slash = "slash";
      comma = "comma";
      period = "period";
      semicolon = "semicolon";
    };

  # What each neutral action means to Aerospace. An action absent from this
  # table is one Aerospace cannot perform; the assertion below reports it by
  # name rather than letting the binding silently do nothing.
  actions = {
    close-window = _: "close";
    fullscreen = _: "fullscreen";
    toggle-floating = _: "layout floating tiling";
    toggle-split-direction = _: "layout tiles horizontal vertical";
    layout-accordion = _: "layout accordion horizontal vertical";

    focus-window = b: "focus ${b.direction}";
    move-window = b: "move ${b.direction}";
    resize-grow = _: "resize smart +50";
    resize-shrink = _: "resize smart -50";

    focus-monitor = b: "focus-monitor ${b.direction}";
    move-window-to-monitor = b: "move-node-to-monitor --focus-follows-window ${b.direction}";
    move-workspace-to-next-monitor = _: "move-workspace-to-monitor --wrap-around next";

    workspace =
      b:
      exec (mkCommandLine {
        package = switchWorkspacePkg;
        args = [ (toString b.workspace) ];
      });
    move-window-to-workspace =
      b:
      exec (mkCommandLine {
        package = moveToWorkspacePkg;
        args = [ (toString b.workspace) ];
      });
    workspace-back-and-forth = _: "workspace-back-and-forth";

    # "open" wants an application name, not a store path, so these cannot go
    # through mkCommandLine the way a Linux exec binding would. That asymmetry
    # is exactly why launching the terminal and the launcher are actions rather
    # than something a host expresses as a "command".
    launcher = _: ''exec-and-forget open -a "Raycast"'';
    terminal = _: ''exec-and-forget open -na "${lib.getName cfg.terminal}"'';

    screenshot-region = _: "exec-and-forget /usr/sbin/screencapture -i -c";
    screenshot-screen = _: "exec-and-forget /usr/sbin/screencapture -c";
  };

  workspaceBindings = lib.listToAttrs (
    lib.concatMap (n: [
      (lib.nameValuePair "workspace-${toString n}" {
        key = toString (lib.mod n 10);
        action = "workspace";
        workspace = n;
      })
      (lib.nameValuePair "move-to-workspace-${toString n}" {
        key = toString (lib.mod n 10);
        modifiers = [ "shift" ];
        action = "move-window-to-workspace";
        workspace = n;
      })
    ]) (lib.range 1 10)
  );

  # h/j/k/l move between displays here, where on Linux they move between
  # windows. Same keys, deliberately different actions: macOS keeps its own
  # window layout per display, so the monitor is the axis worth navigating.
  directionBindings = lib.listToAttrs (
    lib.concatMap
      (
        { key, direction }:
        [
          (lib.nameValuePair "focus-${direction}" {
            inherit key direction;
            action = "focus-monitor";
          })
          (lib.nameValuePair "move-${direction}" {
            inherit key direction;
            modifiers = [ "shift" ];
            action = "move-window-to-monitor";
          })
        ]
      )
      [
        {
          key = "h";
          direction = "left";
        }
        {
          key = "j";
          direction = "down";
        }
        {
          key = "k";
          direction = "up";
        }
        {
          key = "l";
          direction = "right";
        }
      ]
  );

  defaultBindings =
    workspaceBindings
    // directionBindings
    // {
      launcher = {
        key = "d";
        action = "launcher";
      };
      terminal = {
        key = "enter";
        action = "terminal";
      };

      toggle-split-direction = {
        key = "slash";
        action = "toggle-split-direction";
      };
      layout-accordion = {
        key = "comma";
        action = "layout-accordion";
      };

      resize-shrink = {
        key = "minus";
        action = "resize-shrink";
      };
      resize-grow = {
        key = "equal";
        action = "resize-grow";
      };

      workspace-back-and-forth = {
        key = "tab";
        action = "workspace-back-and-forth";
      };
      move-workspace-to-next-monitor = {
        key = "tab";
        modifiers = [ "shift" ];
        action = "move-workspace-to-next-monitor";
      };

      # Same keys as the Linux keymap; both go straight to the clipboard.
      screenshot-region = {
        key = "r";
        modifiers = [ "shift" ];
        action = "screenshot-region";
      };
      screenshot-screen = {
        key = "p";
        modifiers = [ "shift" ];
        action = "screenshot-screen";
      };
    };

  # Bindings that apply to this platform, paired with the name they were given.
  named = lib.mapAttrsToList (name: binding: { inherit name binding; }) cfg.bindings;
  active = lib.filter ({ binding, ... }: binding.enable && lib.elem "darwin" binding.platforms) named;

  mkCombo =
    binding:
    let
      held = lib.unique (
        lib.optional binding.useModifier (lib.toLower cfg.modifier) ++ binding.modifiers
      );
      ordered = lib.filter (m: lib.elem m held) modifierOrder;
    in
    lib.concatStringsSep "-" (map (m: aeroModifiers.${m}) ordered ++ [ aeroKeys.${binding.key} ]);

  mkBinding =
    { binding, ... }:
    lib.nameValuePair (mkCombo binding) (
      if binding.command != null then
        exec (mkCommandLine binding.command)
      else
        actions.${binding.action} binding
    );

  unknownKeys = lib.filter ({ binding, ... }: !(aeroKeys ? ${binding.key})) active;
  unknownActions = lib.filter (
    { binding, ... }: binding.action != null && !(actions ? ${binding.action})
  ) active;

  combos = map ({ binding, ... }: mkCombo binding) (
    lib.filter ({ binding, ... }: aeroKeys ? ${binding.key}) active
  );
  duplicates = lib.unique (lib.filter (combo: lib.count (c: c == combo) combos > 1) combos);
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    assertions = [
      {
        assertion = unknownKeys == [ ];
        message = ''
          These stewos.desktop.bindings name a key this desktop does not know:
          ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.key}\"") unknownKeys}
          See the "key" option for the names it accepts. Note that macOS
          handles the media keys in hardware, so they cannot be bound here.
        '';
      }
      {
        assertion = unknownActions == [ ];
        message = ''
          These stewos.desktop.bindings ask for an action this desktop cannot
          perform:
          ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.action}\"") unknownActions}

          Actions it does support: ${lib.concatStringsSep ", " (lib.attrNames actions)}.
          Restrict the binding with platforms = [ "linux" ] if it is only meant
          for a Linux machine.
        '';
      }
      {
        assertion = duplicates == [ ];
        message = ''
          These key combinations are bound more than once by
          stewos.desktop.bindings: ${lib.concatStringsSep ", " duplicates}.
        '';
      }
    ];

    # Contributed through the option rather than merged in at render time, so
    # "stewos.desktop.bindings" is the single view of what is bound and a host
    # can retarget or disable any of these by name.
    stewos.desktop.bindings = lib.mapAttrs (
      _: binding: lib.mapAttrs (_: lib.mkDefault) binding
    ) defaultBindings;

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

      mode.main.binding = lib.listToAttrs (map mkBinding active) // {
        # The service mode is a backend concept with no counterpart on Linux,
        # so it stays here rather than in the shared binding vocabulary.
        "${lib.toLower cfg.modifier}-shift-semicolon" = "mode service";
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
