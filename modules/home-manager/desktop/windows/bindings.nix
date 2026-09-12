# Keybindings, rendered into whkd's configuration, with komorebi performing
# the window management.
#
# The neutral binding vocabulary declared in ../options.nix arrives here as
# data. This file owns three tables -- modifiers, keys, and actions -- that say
# what each neutral name means to whkd and komorebi, plus the default keymap,
# which is contributed back into "stewos.desktop.bindings" so a host can
# override any of it by name.
{
  options,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.stewos.desktop;

  # Only ever forced inside the guarded config below: pkgs.winpkgs is the
  # winpkgs overlay, which only a Windows home has.
  inherit (pkgs.winpkgs) getExe getExe' toPowerShell;

  # Modifiers are emitted in this order regardless of how they were written, so
  # that two spellings of the same combination render identically.
  modifierOrder = [
    "super"
    "alt"
    "ctrl"
    "shift"
  ];

  modifiers = {
    super = "win";
    alt = "alt";
    ctrl = "ctrl";
    shift = "shift";
  };

  # win-hotkeys' virtual-key names, which whkd matches in any case. No media
  # keys: Windows handles volume and brightness itself, and a hotkey daemon
  # holding them would only take them away from it.
  keys =
    lib.genAttrs (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") lib.id
    // lib.genAttrs (map toString (lib.range 0 9)) lib.id
    // lib.genAttrs (map (n: "f${toString n}") (lib.range 1 12)) lib.id
    // {
      enter = "return";
      space = "space";
      tab = "tab";
      escape = "escape";
      backspace = "back";
      delete = "delete";

      left = "left";
      right = "right";
      up = "up";
      down = "down";

      minus = "oem_minus";
      equal = "oem_plus";
      slash = "oem_2";
      comma = "oem_comma";
      period = "oem_period";
      semicolon = "oem_1";
      bracketleft = "oem_4";
      bracketright = "oem_6";
    };

  # whkd writes every command to one long-lived pwsh session, so a command has
  # to hand back at once: a program started with `&` that stays in the
  # foreground would hold up every binding pressed after it. Start-Process
  # never waits, which makes it the counterpart of Hyprland's exec and
  # Aerospace's exec-and-forget.
  #
  # The arguments go over as one command line, quoted the way Windows splits
  # it back up (CommandLineToArgvW): bare when an argument has no space or
  # quote, otherwise in quotes, with a quote escaped and the backslashes
  # before one -- or before the closing quote -- doubled. That string is then
  # a single-quoted pwsh literal.
  windowsArg =
    arg:
    if arg != "" && builtins.match "[^[:space:]\"]+" arg != null then
      arg
    else
      let
        escaped = lib.concatMapStrings (
          part: if builtins.isList part then "${lib.head part}${lib.head part}\\\"" else part
        ) (builtins.split "(\\\\*)\"" arg);
        trailing = lib.elemAt (builtins.match "(.*[^\\\\])?(\\\\*)" escaped) 1;
      in
      "\"${escaped}${trailing}\"";
  pwshLiteral = s: "'${lib.replaceStrings [ "'" ] [ "''" ] s}'";

  start =
    {
      program,
      args ? [ ],
      extra ? [ ],
    }:
    lib.concatStringsSep " " (
      [
        "Start-Process"
        "\"${toPowerShell program}\""
      ]
      ++ lib.optionals (args != [ ]) [
        "-ArgumentList"
        (pwshLiteral (lib.concatMapStringsSep " " windowsArg args))
      ]
      ++ extra
    );

  # A `command`, found where winpkgs knows its installer puts it.
  run =
    command:
    start {
      program =
        if command.target == null then getExe command.package else getExe' command.package command.target;
      inherit (command) args;
    };

  komorebic = args: "komorebic ${args}";

  # komorebi numbers the workspaces of each monitor from 0; the vocabulary
  # counts from 1, as the keys do.
  index = b: toString (b.workspace - 1);

  # What each neutral action means to komorebi. An action absent from this
  # table is one this desktop cannot perform; the assertion below reports it
  # by name rather than letting the binding silently do nothing.
  actions = {
    close-window = _: komorebic "close";
    minimize-window = _: komorebic "minimize";
    fullscreen = _: komorebic "toggle-maximize";
    toggle-floating = _: komorebic "toggle-float";

    focus-window = b: komorebic "focus ${b.direction}";
    focus-next-window = _: komorebic "cycle-focus next";
    focus-previous-window = _: komorebic "cycle-focus previous";
    move-window = b: komorebic "move ${b.direction}";
    promote-window = _: komorebic "promote";

    stack-window = b: komorebic "stack ${b.direction}";
    unstack-window = _: komorebic "unstack";
    stack-next = _: komorebic "cycle-stack next";
    stack-previous = _: komorebic "cycle-stack previous";

    focus-next-monitor = _: komorebic "cycle-monitor next";
    move-window-to-next-monitor = _: komorebic "cycle-move-to-monitor next";

    # By position on the focused monitor, as hyprsplit and Aerospace do it.
    workspace = b: komorebic "focus-workspace ${index b}";
    workspace-next = _: komorebic "cycle-workspace next";
    workspace-previous = _: komorebic "cycle-workspace previous";
    move-window-to-workspace = b: komorebic "move-to-workspace ${index b}";
    move-window-to-next-workspace = _: komorebic "cycle-move-to-workspace next";
    move-window-to-previous-workspace = _: komorebic "cycle-move-to-workspace previous";
    send-window-to-workspace = b: komorebic "send-to-workspace ${index b}";
    workspace-back-and-forth = _: komorebic "focus-last-workspace";
    move-window-back-and-forth = _: komorebic "move-to-last-workspace";

    launcher = _: config.programs.flow-launcher.showCommand;
    terminal =
      _:
      start {
        program = getExe cfg.terminal;
        extra = [
          "-WorkingDirectory"
          "$Env:USERPROFILE"
        ];
      };

    # Rectangular capture to the clipboard, as Print Screen does.
    screenshot-region = _: "Start-Process ms-screenclip:";

    reload-window-manager = _: komorebic "reload-configuration";
    # whkd reads its configuration once, at start.
    reload-hotkeys = _: "taskkill /f /im whkd.exe; Start-Process whkd -WindowStyle hidden";
    show-shortcuts = _: komorebic "toggle-shortcuts";
  };

  # komorebi keeps five workspaces on each monitor here (./komorebi.nix), so
  # the digits stop at five rather than running to ten as on Linux and macOS.
  workspaceBindings = lib.listToAttrs (
    lib.concatMap (n: [
      (lib.nameValuePair "workspace-${toString n}" {
        key = toString n;
        action = "workspace";
        workspace = n;
      })
      (lib.nameValuePair "move-to-workspace-${toString n}" {
        key = toString n;
        modifiers = [ "shift" ];
        action = "move-window-to-workspace";
        workspace = n;
      })
      (lib.nameValuePair "send-to-workspace-${toString n}" {
        key = toString n;
        modifiers = [ "ctrl" ];
        action = "send-window-to-workspace";
        workspace = n;
      })
    ]) (lib.range 1 5)
  );

  # h/j/k/l focus and move windows, as on Linux; the arrows stack the focused
  # window onto its neighbour.
  directionBindings = lib.listToAttrs (
    lib.concatMap
      (
        {
          key,
          arrow,
          direction,
        }:
        [
          (lib.nameValuePair "focus-${direction}" {
            inherit key direction;
            action = "focus-window";
          })
          (lib.nameValuePair "move-${direction}" {
            inherit key direction;
            modifiers = [ "shift" ];
            action = "move-window";
          })
          (lib.nameValuePair "stack-${direction}" {
            inherit direction;
            key = arrow;
            action = "stack-window";
          })
        ]
      )
      [
        {
          key = "h";
          arrow = "left";
          direction = "left";
        }
        {
          key = "j";
          arrow = "down";
          direction = "down";
        }
        {
          key = "k";
          arrow = "up";
          direction = "up";
        }
        {
          key = "l";
          arrow = "right";
          direction = "right";
        }
      ]
  );

  defaultBindings =
    workspaceBindings
    // directionBindings
    // {
      close-window = {
        key = "q";
        action = "close-window";
      };
      minimize-window = {
        key = "m";
        action = "minimize-window";
      };
      launcher = {
        key = "d";
        action = "launcher";
      };
      terminal = {
        key = "enter";
        action = "terminal";
      };
      promote-window = {
        key = "enter";
        modifiers = [ "shift" ];
        action = "promote-window";
      };
      screenshot-region = {
        key = "r";
        modifiers = [ "shift" ];
        action = "screenshot-region";
      };

      focus-previous-window = {
        key = "bracketleft";
        modifiers = [ "shift" ];
        action = "focus-previous-window";
      };
      focus-next-window = {
        key = "bracketright";
        modifiers = [ "shift" ];
        action = "focus-next-window";
      };
      stack-previous = {
        key = "bracketleft";
        action = "stack-previous";
      };
      stack-next = {
        key = "bracketright";
        action = "stack-next";
      };
      unstack-window = {
        key = "semicolon";
        action = "unstack-window";
      };

      workspace-previous = {
        key = "comma";
        action = "workspace-previous";
      };
      workspace-next = {
        key = "period";
        action = "workspace-next";
      };
      move-to-previous-workspace = {
        key = "comma";
        modifiers = [ "shift" ];
        action = "move-window-to-previous-workspace";
      };
      move-to-next-workspace = {
        key = "period";
        modifiers = [ "shift" ];
        action = "move-window-to-next-workspace";
      };

      # Same key as on macOS.
      workspace-back-and-forth = {
        key = "tab";
        action = "workspace-back-and-forth";
      };
      move-back-and-forth = {
        key = "tab";
        modifiers = [ "shift" ];
        action = "move-window-back-and-forth";
      };

      focus-next-monitor = {
        key = "w";
        action = "focus-next-monitor";
      };
      move-to-next-monitor = {
        key = "w";
        modifiers = [ "shift" ];
        action = "move-window-to-next-monitor";
      };

      reload-window-manager = {
        key = "o";
        modifiers = [ "shift" ];
        action = "reload-window-manager";
      };
      show-shortcuts = {
        key = "i";
        action = "show-shortcuts";
      };
    }
    # Started from the Run key, whkd keeps the old bindings after an apply
    # until something restarts it. As a user service a changed whkdrc restarts
    # it already, and killing it by hand would only race the service manager
    # into running two.
    // lib.optionalAttrs (!config.programs.whkd.service.enable) {
      reload-hotkeys = {
        key = "o";
        action = "reload-hotkeys";
      };
    };

  # Bindings that apply to this platform, paired with the name they were given.
  named = lib.mapAttrsToList (name: binding: { inherit name binding; }) cfg.bindings;
  active = lib.filter (
    { binding, ... }: binding.enable && lib.elem "windows" binding.platforms
  ) named;

  combo =
    held: key:
    let
      ordered = lib.filter (m: lib.elem m held) modifierOrder;
    in
    lib.concatStringsSep " + " (map (m: modifiers.${m}) ordered ++ [ key ]);

  mkCombo =
    binding:
    combo (lib.unique (
      lib.optional binding.useModifier (lib.toLower cfg.modifier) ++ binding.modifiers
    )) keys.${binding.key};

  mkBinding =
    { binding, ... }:
    lib.nameValuePair (mkCombo binding) (
      if binding.command != null then run binding.command else actions.${binding.action} binding
    );

  # Game mode: silences every other binding and pauses tiling; the same
  # combination again resumes both. A whkd directive rather than a binding, so
  # it stays here, as Aerospace's service mode does.
  pause = combo [
    (lib.toLower cfg.modifier)
    "shift"
  ] "p";

  unknownKeys = lib.filter ({ binding, ... }: !(keys ? ${binding.key})) active;
  unknownActions = lib.filter (
    { binding, ... }: binding.action != null && !(actions ? ${binding.action})
  ) active;

  # Only what renders; the rest is reported by the assertions below rather
  # than failing on a missing attribute first.
  renderable = lib.filter (
    { binding, ... }: keys ? ${binding.key} && (binding.action == null || actions ? ${binding.action})
  ) active;

  combos =
    map ({ binding, ... }: mkCombo binding) renderable
    ++ lib.optional (config.programs.whkd.pause != null) config.programs.whkd.pause;
  duplicates = lib.unique (lib.filter (c: lib.count (x: x == c) combos > 1) combos);
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      assertions = [
        {
          assertion = unknownKeys == [ ];
          message = ''
            These stewos.desktop.bindings name a key this desktop does not know:
            ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.key}\"") unknownKeys}
            See the "key" option for the names it accepts. Note that Windows
            handles the media keys itself, so they cannot be bound here.
          '';
        }
        {
          assertion = unknownActions == [ ];
          message = ''
            These stewos.desktop.bindings ask for an action this desktop cannot
            perform:
            ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.action}\"") unknownActions}

            Actions it does support: ${lib.concatStringsSep ", " (lib.attrNames actions)}.
            Restrict the binding with platforms = [ "linux" "darwin" ] if it is
            not meant for Windows.
          '';
        }
        {
          assertion = duplicates == [ ];
          message = ''
            These key combinations are bound more than once by
            stewos.desktop.bindings (or one is whkd's pause combination,
            programs.whkd.pause): ${lib.concatStringsSep ", " duplicates}.
          '';
        }
      ];

      # Contributed through the option rather than merged in at render time, so
      # "stewos.desktop.bindings" is the single view of what is bound and a host
      # can retarget or disable any of these by name.
      stewos.desktop.bindings = lib.mapAttrs (
        _: binding: lib.mapAttrs (_: lib.mkDefault) binding
      ) defaultBindings;

      programs.whkd = {
        enable = true;
        shell = lib.mkDefault "pwsh";
        pause = lib.mkDefault pause;
        pauseHook = lib.mkDefault (komorebic "toggle-pause");

        keybindings = lib.listToAttrs (map mkBinding renderable);
      };
    }
  );
}
