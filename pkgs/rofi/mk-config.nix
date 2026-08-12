# Builder for a Rofi config file: turns an attrset of RASI settings, a theme and
# a list of imports into a package containing /etc/rofi/<name>.
{
  lib,
  writeTextFile,
  rasi,
}:
{
  name,
  imports ? [ ],
  theme,
  settings,
}:
let
  importPaths = lib.forEach imports (
    v:
    if lib.isDerivation v then
      "${v}/etc/rofi/${lib.getName v}"
    else if lib.isString v then
      v
    else
      abort "mkRofiConfig: imports: ${lib.generators.toPretty { } v}: expected string or derivation"
  );
  themePath =
    if lib.isDerivation theme then
      "${theme}/share/rofi/themes/${lib.getName theme}"
    else if lib.isString theme then
      theme
    else
      abort "mkRofiConfig: theme: ${lib.generators.toPretty { } theme}: expected string or derivation";

  importLines = lib.forEach importPaths (v: "@import \"${v}\"");
  extraLines = importLines ++ [ "@theme \"${themePath}\"" ];
  settingsContent = rasi.toRASI settings;
in
writeTextFile {
  inherit name;
  destination = "/etc/rofi/${name}";
  text = lib.concatStringsSep "\n" ([ settingsContent ] ++ extraLines);
}
