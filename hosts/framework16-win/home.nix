# Framework 16, Windows side of the dual boot: the *home* configuration --
# this user, applied as the user, never elevated. The machine's half is
# configuration.nix; see mkHome in flake.nix.
{ lib, ... }:
{
  imports = [ ../common/windows/home.nix ];

  # Per-user installs, each with a user-scope installer, so the home apply
  # never wants elevation. The desktop app was already on the machine; it is
  # written down here beside the CLI rather than left as whatever installed
  # it. Both are `claude.exe` -- the CLI's is winget's portable link -- but
  # only the desktop app has a window, which is what the shared home's
  # komorebi `layered_applications` rule matches.
  winget.packages = [
    "Anthropic.Claude"
    "Anthropic.ClaudeCode"
  ];

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

  # The taskbar is hidden (thide, from the shared home); YASB's battery widget
  # takes its place, and shows itself here because this machine has one.
}
