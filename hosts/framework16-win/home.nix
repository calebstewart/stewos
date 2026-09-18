# Framework 16, Windows side of the dual boot: the *home* configuration --
# this user, applied as the user, never elevated. The machine's half is
# configuration.nix; see mkHome in flake.nix.
{ lib, ... }:
{
  imports = [ ../common/windows/home.nix ];

  programs.komorebi = {
    # The built-in panel: five workspaces, which the workspace keys reach by
    # position. A docked external monitor gets komorebi's defaults.
    settings.monitors = [
      {
        workspaces = map (name: {
          inherit name;
          layout = "BSP";
        }) (lib.stringToCharacters "12345");
      }
    ];
  };
}
