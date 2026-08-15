# Helpers shared by both desktop backends (Hyprland on Linux, Aerospace on
# macOS). Everything here works on values that are already resolved -- a
# package is passed in by value -- so this stays pkgs-free like the rest of
# lib/.
{ lib }:
{
  /**
    Resolve a `{ package, target, args }` triple into an argument vector. With no
    target the package's main program is used, otherwise the named binary from
    its bin directory. Returns a list so the caller can escape it for whichever
    shell its backend runs commands through.

    # Inputs

    `package`
    : The package providing the binary to run.

    `target`
    : Name of a binary in the package's `bin` directory, or `null` (the default)
      to use the package's main program.

    `args`
    : Arguments appended after the resolved binary. Defaults to `[ ]`.

    # Type

    ```
    mkCommandLine :: { package :: Derivation, target :: (String | Null), args :: [String] } -> [String]
    ```

    # Examples

    ```nix
    mkCommandLine { package = pkgs.alacritty; args = [ "-e" "zsh" ]; }
    => [ "/nix/store/...-alacritty/bin/alacritty" "-e" "zsh" ]

    mkCommandLine { package = pkgs.systemd; target = "loginctl"; args = [ "lock-session" ]; }
    => [ "/nix/store/...-systemd/bin/loginctl" "lock-session" ]
    ```
  */
  mkCommandLine =
    {
      package,
      target ? null,
      args ? [ ],
    }:
    [ (if target == null then lib.getExe package else lib.getExe' package target) ] ++ args;
}
