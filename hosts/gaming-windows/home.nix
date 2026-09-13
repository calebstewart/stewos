# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{ lib, ... }:
{
  imports = [ ../common/windows/home.nix ];

  # Edge's auto-launch entry is named after a hash particular to this machine.
  windows.startup."MicrosoftEdgeAutoLaunch_C4BE5320B38C83952663B909BE7916DD" = null;

  # What the desktop leaves to the machine: its two monitors. Five workspaces
  # on each, which the workspace keys reach by position on whichever monitor
  # has focus, and a bar on each (komorebi's monitor indices).
  programs.komorebi = {
    settings.monitors =
      let
        # One BSP workspace per character of `names`.
        monitor = names: {
          workspaces = map (name: {
            inherit name;
            layout = "BSP";
          }) (lib.stringToCharacters names);
        };
      in
      [
        (monitor "12345")
        (monitor "67890")
      ];

    bar.monitors = {
      "0" = { };
      "1" = { };
    };
  };
}
