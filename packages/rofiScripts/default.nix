{
  lib,
  callPackage,
  writeShellApplication,
}:
let
  # This is an alias for now, but might change
  mkRofiScript = writeShellApplication;
in
(lib.foldlAttrs (
  acc: name: type:
  acc
  // (
    if type == "directory" then
      {
        "${name}" = callPackage (./. + "/${name}/default.nix") {
          inherit mkRofiScript;
        };
      }
    else
      { }
  )
) { } (builtins.readDir ./.))
// {
  inherit mkRofiScript;
}
