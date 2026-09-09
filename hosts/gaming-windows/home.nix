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

    # Pointer/Cursor
    pointer = {
      style = "black";
      size = "normal";
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

  programs.windows-terminal = {
    enable = true;
    settings.profiles.defaults.font.face = "JetBrainsMono Nerd Font Mono";
    settings.copyOnSelect = true;
    base16 = { palette = config.colorScheme.palette; name = "Catppuccin Mocha"; };
  };

  programs.whkd = {
    enable = true;
    shell = "pwsh";                  # your current file says powershell; pwsh is on the machine
    pause = "alt + shift + p";       # toggles every other binding

    keybindings = {
      # whkd reads whkdrc once: after a `winpkgs home switch`, press this.
      "alt + o" = "taskkill /f /im whkd.exe; Start-Process whkd -WindowStyle hidden";
      "alt + shift + o" = "komorebic reload-configuration";
      "alt + i" = "komorebic toggle-shortcuts";

      # focus a window if open, else launch ($wshell is whkd's WScript.Shell)
      "alt + return" = ''Start-Process "C:\Program Files\Alacritty\alacritty.exe"'';

      "alt + q" = "komorebic close";
      "alt + m" = "komorebic minimize";

      # focus
      "alt + h" = "komorebic focus left";
      "alt + j" = "komorebic focus down";
      "alt + k" = "komorebic focus up";
      "alt + l" = "komorebic focus right";
      "alt + shift + oem_4" = "komorebic cycle-focus previous";   # oem_4 is [
      "alt + shift + oem_6" = "komorebic cycle-focus next";       # oem_6 is ]

      # move
      "alt + shift + h" = "komorebic move left";
      "alt + shift + j" = "komorebic move down";
      "alt + shift + k" = "komorebic move up";
      "alt + shift + l" = "komorebic move right";
      "alt + shift + return" = "komorebic promote";

      # stack
      "alt + left" = "komorebic stack left";
      "alt + down" = "komorebic stack down";
      "alt + up" = "komorebic stack up";
      "alt + right" = "komorebic stack right";
      "alt + oem_1" = "komorebic unstack";                # oem_1 is ;
      "alt + oem_4" = "komorebic cycle-stack previous";
      "alt + oem_6" = "komorebic cycle-stack next";

      # per application: close everything with alt+q except Chrome, which keeps the keys
      "alt + w" = {
        Default = "komorebic close";
        "Google Chrome" = "Ignore";
      };
    };
  };
}
