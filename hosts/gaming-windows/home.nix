# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    git
    ripgrep
  ];

  winpkgs.theme.mode = "dark";
  winpkgs.keyboard.stickyKeysShortcut = false;

  # Configure the task bar
  winpkgs.taskbar = {
    alignment = "left";
    searchBox = "hidden";
    widgets = false;
    chat = false;
    taskViewButton = false;
    showOnAllDisplays = true;
    combineButtons = "whenFull";
  };

  # Configure Windows Explorer
  winpkgs.explorer = {
    contextMenu = "classic";
    showHiddenFiles = true;
    showFileExtensions = true;
    showProtectedOsFiles = true;
    launchTo = "home";
    compactMode = true;
    expandToCurrentFolder = true;
    hideDrivesWithNoMedia = true;
    showSyncProviderNotifications = false;
  };

  # Configure powershell
  winpkgs.powershell = {
    ensure = true;
    upgrade = true;
  };

  # Configure Windows "privacy" options; the machine-wide ones are in configuration.nix.
  winpkgs.privacy = {
    advertisingId = false;
    suggestedContent = false;
    suggestedApps = false;
    tips = false;
    webSearchInStart = false;
  };

  stewos = {
    git.enable = true;
    git.forceSSH = true;

    neovim.enable = true;
  };

  # Where this flake is checked out on the Windows side, so `winpkgs plan` etc.
  # work from any Windows terminal without naming it.
  winpkgs.cli.flake = ''%USERPROFILE%\git\stewos'';

  # Sets XDG_CONFIG_HOME, so Neovim (and git, starship, ...) read ~/.config on
  # Windows too, where winpkgs puts xdg.configFile.
  xdg.enable = true;
}
