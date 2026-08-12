# Builder for Rofi themes: turns an attrset of RASI settings into a package
# containing /share/rofi/themes/<name>.
{
  lib,
  writeTextFile,
  rasi,
}:
args@{
  imports ? [ ],
  settings,
  ...
}:
let
  # For each import, construct the nix-store path for derivations or use explicit string
  # if not a derivation.
  importPaths = lib.lists.forEach imports (
    v:
    if lib.isDerivation v then
      "${v}/etc/rofi/${lib.getName v}"
    else if lib.isString v then
      v
    else
      abort "mkRofiTheme: imports: ${lib.generators.toPretty { } v}: expected string or derivation"
  );

  # Construct the import lines
  importLines = lib.lists.forEach importPaths (v: "@import \"${v}\"");
  settingsContent = rasi.toRASI settings;
in
writeTextFile (
  (removeAttrs args [
    "imports"
    "settings"
  ])
  // {
    destination = "/share/rofi/themes/${args.name}";
    text = lib.strings.concatStringsSep "\n" ([ settingsContent ] ++ importLines);
  }
)
