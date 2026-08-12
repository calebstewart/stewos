# Rofi command line construction. Kept beside ./rasi, which generates the
# themes these arguments select.
{ lib }:
{
  # Build the argument list that shows rofi with a set of modes.
  #
  # A mode is either the name of one rofi already knows ("drun", "window"), or
  # a package implementing a script mode. For a package the derivation name
  # becomes the mode name and its main program the script, which is the pairing
  # rofi's "-modes name:path" syntax wants.
  mkModeArgs =
    {
      modes,
      theme ? null,
    }:
    let
      scriptModes = lib.concatMap (
        mode: lib.optional (lib.isDerivation mode) "${lib.getName mode}:${lib.getExe mode}"
      ) modes;

      modeNames = map (mode: if lib.isDerivation mode then lib.getName mode else mode) modes;
    in
    [
      "-show"
      (lib.concatStringsSep "," modeNames)
    ]
    ++ lib.optionals (theme != null) [
      "-theme"
      theme
    ]
    ++ lib.optionals (scriptModes != [ ]) [
      "-modes"
      (lib.concatStringsSep "," scriptModes)
    ];
}
