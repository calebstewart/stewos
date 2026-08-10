{ nixpkgs, ... }:
let
  lib = nixpkgs.lib;

  # Render a Nix value as a Lua literal. Used for every string we splice into a
  # generated Lua expression so quoting/escaping is never hand-rolled.
  toLua = lib.generators.toLua { };
in
rec {
  # Wrap a raw Lua expression so home-manager's Hyprland Lua renderer emits it
  # verbatim instead of quoting it as a string.
  mkLua = lib.generators.mkLuaInline;

  # Create a position string from attrs with ".x" and ".y". The result is a string
  # like "100x150" for input { x = 100; y = 150 }.
  mkPosition = p: "${toString p.x}x${toString p.y}";

  # Create a resolution string. This is similar to mkPosition, but the input object
  # has attrs "width" and "height". The literal "preferred" is passed through.
  mkResolution = r: if lib.isString r then r else "${toString r.width}x${toString r.height}";

  # Create the argument table for an "hl.monitor" call from an attrset like:
  # { description = ""; resolution = { width = 1; height = 1; }; position = { x = 1; y = 1; }; scale = 1.0; }
  mkMonitorSpec = mon: {
    output = "desc:${mon.description}";
    mode = mkResolution mon.resolution;
    position = mkPosition mon.position;
    scale = mon.scale;
  };

  # Build the key combination string used by "hl.bind" (e.g. "ALT + SHIFT + Q").
  # The modifier is a space separated list of modifier names and may be empty,
  # in which case the bare key name is returned.
  mkKeys =
    modifier: key:
    let
      modifiers = lib.filter (m: m != "") (lib.splitString " " modifier);
    in
    lib.concatStringsSep " + " (modifiers ++ [ key ]);

  # Create the "hl.bind" call arguments for Hyprland. The dispatcher is a raw Lua
  # expression (see mkLua/mkDispatcher), and opts is an optional table of bind
  # flags such as { locked = true; repeating = true; }.
  mkBinding =
    {
      modifier,
      key,
      dispatcher,
      opts ? null,
    }:
    {
      _args = [
        (mkKeys modifier key)
        dispatcher
      ]
      ++ lib.optional (opts != null) opts;
    };

  # Create a Lua dispatcher expression, e.g.
  #   mkDispatcher "hl.dsp.focus" { direction = "l"; }
  # becomes the Lua expression 'hl.dsp.focus({ ["direction"] = "l" })'.
  # Passing null calls the dispatcher with no arguments.
  mkDispatcher = name: args: mkLua "${name}(${if args == null then "" else toLua args})";

  # Create the command line string for an exec dispatcher. If no target is provided,
  # then 'lib.meta.getExe' is used on the given package. The argument list is appended
  # to the executable path.
  mkExecCommand =
    {
      package,
      target ? null,
      args ? [ ],
    }:
    let
      executablePath = if target == null then (lib.meta.getExe package) else "${package}/bin/${target}";
    in
    lib.escapeShellArgs ([ executablePath ] ++ args);

  # Create an exec binding for Hyprland. See mkExecCommand for how the command line
  # is resolved from the package/target/args triple.
  mkExecBinding =
    {
      modifier,
      key,
      package,
      target ? null,
      args ? [ ],
      opts ? null,
    }:
    mkBinding {
      inherit modifier key opts;
      dispatcher = mkDispatcher "hl.dsp.exec_cmd" (mkExecCommand {
        inherit package target args;
      });
    };
}
