# Windows 11 desktop, and the NixOS-WSL distro on it that evaluates and applies
# this configuration. See mkWindowsHost in flake.nix.
{ ... }:
{
  # Bare minimum to prove the pipeline. (PowerShell 7 is not listed: winpkgs
  # ensures and upgrades it itself, since its runtime depends on it.)
  winpkgs.packages.winget = [
    "Git.Git"
  ];

  winpkgs.theme.mode = "dark";
  winpkgs.developer.developerMode = true;
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

  # Configure Windows "privacy" options
  winpkgs.privacy = {
    advertisingId = false;
    suggestedContent = false;
    suggestedApps = false;
    tips = false;
    webSearchInStart = false;
    activityFeed = false;
    telemetry = "required";
  };

  # Where this flake is checked out on the Windows side, so `winpkgs plan` etc.
  # work from any Windows terminal without naming it.
  winpkgs.cli.flake = ''%USERPROFILE%\git\stewos'';

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  winpkgs.wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
