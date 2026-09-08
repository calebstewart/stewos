# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{
  inputs,
  pkgs,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    git
    ripgrep
  ];

  # The same palette as every other host; stewos.neovim renders it.
  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  windows.theme.mode = "dark";
  windows.keyboard.stickyKeysShortcut = false;

  # Configure the task bar
  windows.taskbar = {
    alignment = "left";
    searchBox = "hidden";
    widgets = false;
    chat = false;
    taskViewButton = false;
    showOnAllDisplays = true;
    combineButtons = "whenFull";
  };

  # Configure Windows Explorer
  windows.explorer = {
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
  windows.privacy = {
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
    alacritty.enable = true;
  };

  # Where this flake is checked out on the Windows side, so `winpkgs plan` etc.
  # work from any Windows terminal without naming it.
  winpkgs.cli.flake = ''%USERPROFILE%\git\stewos'';

  # Sets XDG_CONFIG_HOME, so Neovim (and git, starship, ...) read ~/.config on
  # Windows too, where winpkgs puts xdg.configFile.
  xdg.enable = true;
}
