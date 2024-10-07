{inputs, stewos, ...}: 
let
  lib = inputs.nixpkgs.lib;
in rec {
  # Create a binding string for Hyprland (e.g. the arguments to the "bind" command)
  mkBinding = {modifiers, key, dispatcher, args ? ""}: lib.strings.concatStringsSep "," [
    (lib.strings.concatStringsSep " " modifiers)
    key
    dispatcher
    args
  ];

  # Create an exec binding for Hyprland. If no target is provided, then 'lib.meta.getExe' is used on the
  # given package. The argument list is appended to the executable path.
  mkExecBinding = {modifiers, key, package, target ? null, args ? []}:
  let
    executablePath = if target == null then (lib.meta.getExe package) else "${package}/bin/${target}";
  in mkBinding {
    inherit modifiers key;
    dispatcher = "exec";
    args = lib.strings.concatStringsSep " " ([executablePath] ++ args);
  };

  # Create an exec binding which runs rofi with the given theme, mode, and custom mode list.
  mkRofiBinding = {package, modifiers, key, theme ? null, mode, customModes ? {}}:
  let
    buildMode = acc: name: mode: acc ++ ["${name}:${lib.meta.getExe mode}"];
    buildOptionPair = acc: key: val: if (val != "") && (val != null) then acc ++ ["-${key}" val] else acc;
    args = lib.attrsets.foldlAttrs buildOptionPair [] {
      inherit theme;
      show = if lib.isList mode then lib.strings.concatStringsSep "," mode else toString mode;
      modes = lib.strings.concatStringsSep "," (lib.attrsets.foldlAttrs buildMode [] customModes);
    };
  in mkExecBinding {
    inherit modifiers key args package;
  };
}
