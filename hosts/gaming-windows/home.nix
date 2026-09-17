# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{ lib, ... }:
{
  imports = [ ../common/windows/home.nix ];

  # Per-user installs, each with a user-scope installer, so the home apply
  # never wants elevation. The machine-wide half is configuration.nix.
  winget.packages = [
    "Anthropic.Claude"
    "Discord.Discord" # the ordinary installer, not the Store's XPDC2RH70K22MN

    # Toolchains.
    "Rustlang.Rustup"
    "Microsoft.WinDbg"
  ];

  windows.startup = {
    # Edge's auto-launch entry is named after a hash particular to this machine.
    "MicrosoftEdgeAutoLaunch_C4BE5320B38C83952663B909BE7916DD" = null;

    # Steam comes up with the session, quietly: no client window, just the
    # tray icon and the library ready.
    Steam = ''"C:\Program Files (x86)\Steam\steam.exe" -silent'';

    # Discord writes a Run entry of its own, and its in-app "open on startup"
    # switch is what edits it. Declaring it here would take that switch away
    # -- the next apply would put the entry back -- so it is left alone.

    # AMD's microphone noise suppression, which is what stewos.audio's rnnoise
    # filter chain is on the Framework machines: a tray program AMD Software
    # installs beside the driver, started from this user's Run key. Wanted, so
    # it is written down rather than left as whatever the installer did.
    AMDNoiseSuppression = ''"C:\WINDOWS\system32\AMD\ANR\AMDNoiseSuppression.exe"'';
  };

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
