# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    git
    ripgrep
    thide # hides the taskbar; see stewos.desktop.bindings.taskbar
  ];

  # Install packages explicitly from winget
  winget.packages = [ "Fastfetch-cli.Fastfetch" ];

  # The same palette as every other host; the desktop, stewos.neovim and the
  # terminals below all render it.
  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  # Windows system settings. The theme, wallpaper and console palette come
  # from stewos.desktop.
  windows = {
    keyboard.stickyKeysShortcut = false;

    # Disable some default or unwanted auto-start entries
    startup = {
      OneDrive = null;
      # thide in tray mode hides the taskbar as it starts; the "taskbar"
      # binding below toggles it.
      THide = ''"%LOCALAPPDATA%\Programs\thide\thide.exe"'';
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
    # komorebi, whkd, Flow Launcher and masir, on the same keymap as the
    # Linux machines. See modules/home-manager/desktop/windows.
    desktop = {
      enable = true;
      modifier = "ALT";

      # Show or hide the taskbar.
      bindings.taskbar = {
        key = "b";
        command = {
          package = pkgs.thide;
          args = [ "toggle" ];
        };
      };
    };

    git.enable = true;
    git.forceSSH = true;
    neovim.enable = true;
    alacritty.enable = true;
    eza.enable = true;
    zoxide.enable = true;
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

  # Alacritty's built-in default shell on Windows is Windows PowerShell 5.1;
  # run pwsh 7, which programs.powershell below configures.
  programs.alacritty.settings.terminal.shell = {
    program = "pwsh";
    args = [ "-NoLogo" ];
  };

  # The prompt: home-manager's own module; winpkgs installs it from winget and
  # hooks it into the PowerShell profile below.
  programs.oh-my-posh = {
    enable = true;
    useTheme = "catppuccin_mocha";
  };

  programs.powershell = {
    enable = true;
    psReadLine.options = {
      EditMode = "Emacs";
      PredictionSource = "History";
      PredictionViewStyle = "ListView";
      HistoryNoDuplicates = true;
    };
    shellAliases = {
      g = "git";
      ll = "Get-ChildItem -Force";
      vim = "nvim";
    };
  };

  programs.windows-terminal = {
    enable = true;
    settings.profiles.defaults.font.face = config.stewos.desktop.fonts.monospace.name;
    settings.copyOnSelect = true;
    base16 = {
      inherit (config.colorScheme) palette name;
    };
  };

  programs.gh.enable = true;

  # What the desktop leaves to the machine: its two monitors. Five workspaces
  # on each, which the workspace keys reach by position on whichever monitor
  # has focus, and a bar on each (komorebi's monitor indices).
  programs.komorebi = {
    settings = {
      monitors =
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

      layered_applications = [
        {
          kind = "Exe";
          id = "claude.exe";
          matching_strategy = "Equals";
        }
      ];
    };

    bar.monitors = {
      "0" = { };
      "1" = { };
    };
  };
}
