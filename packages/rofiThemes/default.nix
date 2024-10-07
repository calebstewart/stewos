{
  lib,
  writeTextFile,
  stewos,
  inputs,
  callPackage,
}:
let
  mkRofiTheme = args@{imports ? [], settings, ...}:
  let
    # For each import, construct the nix-store path for derivations or use explicit string
    # if not a derivation.
    importPaths = lib.lists.forEach imports (v:
      if lib.isDerivation v then "${v}/etc/rofi/${lib.getName v}"
      else if lib.isString then v
      else abort "mkRofiTheme: imports: ${lib.generators.toPretty v}: expected string or derivation"
    );

    # Construct the import lines
    importLines = lib.lists.forEach importPaths (v: "@import \"${v}\"");
    settingsContent = stewos.lib.rasi.toRASI settings;
  in writeTextFile ((removeAttrs args ["imports" "settings"]) // {
    destination = "/share/rofi/themes/${args.name}";
    text = lib.strings.concatStringsSep "\n" ([settingsContent] ++ importLines);
  });

  stewosFn = import ./stewos.nix;
in {
  # Expose a function to create new rofi themes
  inherit mkRofiTheme;

  # Expose default stewos theme which uses the default color scheme
  stewos = callPackage stewosFn {
    inherit mkRofiTheme;
  };
}
