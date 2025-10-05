{nixpkgs, ...}: 
let
  lib = nixpkgs.lib;
in rec {
  # Create a position string from attrs with ".x" and ".y". The result is a string
  # like "100x150" for input { x = 100; y = 150 }.
  mkPosition = p: "${toString p.x}x${toString p.y}";

  # Create a resolution string. This is similar to mkPosition, but the input object
  # has attrs "width" and "height".
  mkResolution = r: "${toString r.width}x${toString r.height}";

  # Create a monitor configuration from an attrset like:
  # { description = ""; resolution = { x = 1; y = 1; }; position = { x = 1; y = 1; }; }
  mkMonitorConfig = mon: "desc:${mon.description},${mkResolution mon.resolution},${mkPosition mon.position},${toString mon.scale}";

  # Create a binding string for Hyprland (e.g. the arguments to the "bind" command)
  mkBinding = {modifier, key, dispatcher, args ? ""}:
  let
    normalizedArgs = if lib.isList args then (lib.concatStringsSep " " args) else args;
  in lib.strings.concatStringsSep "," [
    modifier
    key
    dispatcher
    normalizedArgs
  ];

  # Create an exec binding for Hyprland. If no target is provided, then 'lib.meta.getExe' is used on the
  # given package. The argument list is appended to the executable path.
  mkExecBinding = {modifier, key, package, target ? null, args ? []}:
  let
    executablePath = if target == null then (lib.meta.getExe package) else "${package}/bin/${target}";
  in mkBinding {
    inherit modifier key;
    dispatcher = "exec";
    args = lib.escapeShellArgs ([executablePath] ++ args);
  };
}
