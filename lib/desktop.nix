# Helpers shared by both desktop backends (Hyprland on Linux, Aerospace on
# macOS). Everything here works on values that are already resolved -- a
# package is passed in by value -- so this stays pkgs-free like the rest of
# lib/.
{ lib }:
{
  # Resolve a { package, target, args } triple into an argument vector. With no
  # target the package's main program is used, otherwise the named binary from
  # its bin directory. Returns a list so the caller can escape it for whichever
  # shell its backend runs commands through.
  mkCommandLine =
    {
      package,
      target ? null,
      args ? [ ],
    }:
    [ (if target == null then lib.getExe package else lib.getExe' package target) ] ++ args;
}
