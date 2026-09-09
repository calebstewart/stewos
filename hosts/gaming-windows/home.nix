# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{
  inputs,
  pkgs,
  config,
  ...
}: let
  winpkgs = inputs.winpkgs;
in {
  home.packages = with pkgs; [
    git
    ripgrep
    # The terminal font stewos.alacritty asks for; a font in home.packages is
    # installed for this user from its files, as on the Linux hosts.
    nerd-fonts.jetbrains-mono
  ];

  # The same palette as every other host; stewos.neovim renders it.
  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  # Windows system settings
  windows = {
    keyboard.stickyKeysShortcut = false;

    theme = {
      mode = "dark";
      wallpaper.image = config.stewos.desktop.wallpaper;
      accentColor = "#${config.colorScheme.palette.base0D}";
      background = "#${config.colorScheme.palette.base00}";
      accentColorInactive = "#${config.colorScheme.palette.base02}";
      accentOnStartAndTaskbar = true;
      accentOnTitleBars = true;
    };
    
    # Set the default console (ConHost) color scheme
    console.base16 = config.colorScheme.palette;

    # Disable some default or unwanted auto-start entries
    startup = {
      OneDrive = null;
      "MicrosoftEdgeAutoLaunch_C4BE5320B38C83952663B909BE7916DD" = null;
    };

    # Configure the task bar
    taskbar = {
      alignment = "left";
      searchBox = "hidden";
      widgets = false;
      chat = false;
      taskViewButton = false;
      showOnAllDisplays = true;
      combineButtons = "whenFull";
    };

    # Configure Windows Explorer
    explorer = {
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

    # Configure Windows "privacy" options; the machine-wide ones are in configuration.nix.
    privacy = {
      advertisingId = false;
      suggestedContent = false;
      suggestedApps = false;
      tips = false;
      webSearchInStart = false;
    };
  };

  # Shared StewOS configurations we opt into
  stewos = {
    git.enable = true;
    git.forceSSH = true;
    neovim.enable = true;
    alacritty.enable = true;
  };

  # Sets XDG_CONFIG_HOME, so Neovim (and git, starship, ...) read ~/.config on
  # Windows too, where winpkgs puts xdg.configFile.
  xdg.enable = true;

  # Winpkgs internal settings
  winpkgs = {
    # Where this flake is checked out on the Windows side, so `winpkgs plan` etc.
    # work from any Windows terminal without naming it.
    cli.flake = ''%USERPROFILE%\git\stewos'';

    powershell = {
      ensure = true;
      upgrade = true;
    };
  };

  programs.alacritty.settings = {
    window.decorations = "Buttonless";
    window.startup_mode = "windowed";
  };
}
