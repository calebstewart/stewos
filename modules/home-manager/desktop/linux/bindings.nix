# Keybindings, rendered onto Hyprland's Lua config API.
#
# The neutral binding vocabulary declared in ../options.nix arrives here as
# data. This file owns three tables -- modifiers, keys, and actions -- that say
# what each neutral name means to Hyprland, plus the default keymap, which is
# contributed back into "stewos.desktop.bindings" so a host can override any of
# it by name.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.stewos.desktop;

  inherit (inputs.self.lib.desktop) mkCommandLine;
  inherit (inputs.self.lib.rofi) mkModeArgs;

  # Wrap a raw Lua expression so home-manager's renderer emits it verbatim
  # rather than quoting it as a string.
  mkLua = lib.generators.mkLuaInline;

  # "hl.dsp.focus({ ["direction"] = "l" })". Passing null calls the dispatcher
  # with no arguments.
  mkDispatcher =
    name: args: mkLua "${name}(${if args == null then "" else lib.generators.toLua { } args})";

  exec = argv: mkDispatcher "hl.dsp.exec_cmd" (lib.escapeShellArgs argv);
  run = command: exec (mkCommandLine command);

  # Modifiers are emitted in this order regardless of how they were written, so
  # that two spellings of the same combination render identically.
  modifierOrder = [
    "super"
    "ctrl"
    "alt"
    "shift"
  ];

  hyprModifiers = {
    super = "SUPER";
    ctrl = "CTRL";
    alt = "ALT";
    shift = "SHIFT";
  };

  hyprKeys =
    lib.genAttrs (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") lib.toUpper
    // lib.genAttrs (map toString (lib.range 0 9)) lib.id
    // lib.genAttrs (map (n: "f${toString n}") (lib.range 1 12)) lib.toUpper
    // {
      enter = "Return";
      space = "Space";
      tab = "Tab";
      escape = "Escape";
      backspace = "Backspace";
      delete = "Delete";

      left = "Left";
      right = "Right";
      up = "Up";
      down = "Down";

      minus = "minus";
      equal = "equal";
      slash = "slash";
      comma = "comma";
      period = "period";
      semicolon = "semicolon";

      "volume-up" = "XF86AudioRaiseVolume";
      "volume-down" = "XF86AudioLowerVolume";
      "volume-mute" = "XF86AudioMute";
      "brightness-up" = "XF86MonBrightnessUp";
      "brightness-down" = "XF86MonBrightnessDown";
    };

  hyprDirections = {
    left = "l";
    right = "r";
    up = "u";
    down = "d";
  };

  wpctl = args: exec ([ (lib.getExe' pkgs.wireplumber "wpctl") ] ++ args);
  setVolume =
    step:
    wpctl [
      "set-volume"
      "-l"
      "1"
      "@DEFAULT_AUDIO_SINK@"
      step
    ];
  grimblast =
    args:
    run {
      package = pkgs.grimblast;
      inherit args;
    };

  # What each neutral action means to Hyprland. An action absent from this
  # table is one Hyprland cannot perform; the assertion below reports it by
  # name rather than letting the binding fail at compositor startup.
  #
  # "hyprsplit" is the local declared in ./hyprland.nix, which is why the
  # workspace actions can reference it.
  actions = {
    close-window = _: mkDispatcher "hl.dsp.window.close" null;
    fullscreen = _: mkDispatcher "hl.dsp.window.fullscreen" null;
    toggle-floating = _: mkDispatcher "hl.dsp.window.float" { action = "toggle"; };
    toggle-split-direction = _: mkDispatcher "hl.dsp.layout" "togglesplit";

    focus-window = b: mkDispatcher "hl.dsp.focus" { direction = hyprDirections.${b.direction}; };
    move-window = b: mkDispatcher "hl.dsp.window.move" { direction = hyprDirections.${b.direction}; };

    workspace = b: mkDispatcher "hyprsplit.dsp.focus" { workspace = toString b.workspace; };
    move-window-to-workspace =
      b: mkDispatcher "hyprsplit.dsp.window.move" { workspace = toString b.workspace; };

    launcher = _: mkDispatcher "hl.dsp.global" "caelestia:launcher";
    brightness-up = _: mkDispatcher "hl.dsp.global" "caelestia:brightnessUp";
    brightness-down = _: mkDispatcher "hl.dsp.global" "caelestia:brightnessDown";

    volume-up = _: setVolume "5%+";
    volume-down = _: setVolume "5%-";
    volume-mute =
      _:
      wpctl [
        "set-mute"
        "@DEFAULT_AUDIO_SINK@"
        "toggle"
      ];

    terminal = _: run { package = cfg.terminal; };
    lock-session =
      _:
      run {
        package = pkgs.systemd;
        target = "loginctl";
        args = [ "lock-session" ];
      };

    screenshot-region =
      _:
      grimblast [
        "copy"
        "area"
        "--notify"
      ];
    screenshot-screen =
      _:
      grimblast [
        "copy"
        "output"
        "--notify"
      ];
  };

  # Rofi is a separate module, and a host may have turned it off. Build its
  # bindings only when it is actually configured, rather than pulling an
  # unconfigured rofi into the closure for a key that would look broken anyway.
  rofiCommand =
    {
      modes,
      theme ? null,
    }:
    {
      package = config.stewos.rofi.package;
      args = mkModeArgs { inherit modes theme; };
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

  directionBindings = lib.listToAttrs (
    lib.concatMap
      (
        { key, direction }:
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
      # Media keys fire on their own, without the global prefix.
      volume-up = {
        key = "volume-up";
        useModifier = false;
        action = "volume-up";
      };
      volume-down = {
        key = "volume-down";
        useModifier = false;
        action = "volume-down";
      };
      brightness-up = {
        key = "brightness-up";
        useModifier = false;
        action = "brightness-up";
      };
      brightness-down = {
        key = "brightness-down";
        useModifier = false;
        action = "brightness-down";
      };

      close-window = {
        key = "q";
        action = "close-window";
      };
      launcher = {
        key = "d";
        action = "launcher";
      };
      toggle-split-direction = {
        key = "v";
        action = "toggle-split-direction";
      };
      terminal = {
        key = "enter";
        action = "terminal";
      };
      lock-session = {
        key = "backspace";
        action = "lock-session";
      };

      fullscreen = {
        key = "f";
        modifiers = [ "shift" ];
        action = "fullscreen";
      };
      toggle-floating = {
        key = "space";
        modifiers = [ "shift" ];
        action = "toggle-floating";
      };
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

      new-uuid = {
        key = "u";
        command.package = pkgs.stewos.wl-gen-uuid;
      };
    }
    // lib.optionalAttrs config.stewos.rofi.enable {
      vm-menu = {
        key = "m";
        command = rofiCommand { modes = [ pkgs.stewos.rofi-libvirt ]; };
      };
      power-menu = {
        key = "e";
        modifiers = [ "shift" ];
        command = rofiCommand { modes = [ pkgs.stewos.rofi-hyprpower ]; };
      };
    };

  # Bindings that apply to this platform, paired with the name they were given.
  named = lib.mapAttrsToList (name: binding: { inherit name binding; }) cfg.bindings;
  active = lib.filter ({ binding, ... }: binding.enable && lib.elem "linux" binding.platforms) named;

  mkCombo =
    binding:
    let
      held = lib.unique (
        lib.optional binding.useModifier (lib.toLower cfg.modifier) ++ binding.modifiers
      );
      ordered = lib.filter (m: lib.elem m held) modifierOrder;
    in
    lib.concatStringsSep " + " (map (m: hyprModifiers.${m}) ordered ++ [ hyprKeys.${binding.key} ]);

  mkBind =
    { binding, ... }:
    {
      _args = [
        (mkCombo binding)
        (if binding.command != null then run binding.command else actions.${binding.action} binding)
      ];
    };

  unknownKeys = lib.filter ({ binding, ... }: !(hyprKeys ? ${binding.key})) active;
  unknownActions = lib.filter (
    { binding, ... }: binding.action != null && !(actions ? ${binding.action})
  ) active;

  combos = map ({ binding, ... }: mkCombo binding) (
    lib.filter ({ binding, ... }: hyprKeys ? ${binding.key}) active
  );
  duplicates = lib.unique (lib.filter (combo: lib.count (c: c == combo) combos > 1) combos);
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    assertions = [
      {
        assertion = unknownKeys == [ ];
        message = ''
          These stewos.desktop.bindings name a key this desktop does not know:
          ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.key}\"") unknownKeys}
          See the "key" option for the names it accepts.
        '';
      }
      {
        assertion = unknownActions == [ ];
        message = ''
          These stewos.desktop.bindings ask for an action this desktop cannot
          perform:
          ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: \"${b.binding.action}\"") unknownActions}

          Actions it does support: ${lib.concatStringsSep ", " (lib.attrNames actions)}.
          Restrict the binding with platforms = [ "darwin" ] if it is only
          meant for a Mac.
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

    wayland.windowManager.hyprland.settings.bind = map mkBind active;
  };
}
