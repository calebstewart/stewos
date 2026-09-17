# Policy shared by the Windows machines' *home* configurations -- HKCU,
# %USERPROFILE%, the shell -- applied as the user, never elevated. The
# machine's half is ./configuration.nix.
#
# What a machine still says for itself is its monitors (komorebi's workspaces
# and bars) and anything else only it has; see each host's home.nix.
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
    thide # hides the taskbar; see stewos.desktop.bindings.taskbar
  ];

  # Install packages explicitly from winget. Windows Terminal is here rather
  # than in a host because programs.windows-terminal below configures it for
  # every Windows machine and, until now, none of them installed it.
  winget.packages = [
    "Fastfetch-cli.Fastfetch"
    "Microsoft.WindowsTerminal"
  ];

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
      # steward runs thide now (systemd.user.services.thide, below).
      THide = null;
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

    # Configure Windows "privacy" options; the machine-wide ones are in ./configuration.nix.
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
    # The same prompt as the zsh hosts, with the root segment lit under
    # `sudo pwsh`. winpkgs installs oh-my-posh from winget, and its
    # programs.powershell hooks the generated config.json into the profile
    # below.
    oh-my-posh.enable = true;
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

  programs.gsudo = {
    settings = {
      PowerShellLoadProfile = true;
    };
    enablePowerShellIntegration = true;
    sudoAlias = true;
  };

  # Alacritty's built-in default shell on Windows is Windows PowerShell 5.1;
  # run pwsh 7, which programs.powershell below configures.
  programs.alacritty.settings.terminal.shell = {
    program = "pwsh";
    args = [ "-NoLogo" ];
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

  programs.komorebi.settings.layered_applications = [
    {
      kind = "Exe";
      id = "claude.exe";
      matching_strategy = "Equals";
    }
  ];

  # thide in tray mode hides the taskbar while it runs; the "taskbar" binding
  # toggles it, and `thide stop` gives the taskbar back. A steward unit, like
  # the desktop's daemons (komorebi, whkd and masir: see
  # modules/home-manager/desktop/windows/services.nix). home.homeDirectory is
  # the real profile directory once winpkgs writes the unit.
  systemd.user.services.thide =
    let
      exe = "${config.home.homeDirectory}/AppData/Local/Programs/thide/thide.exe";
    in
    {
      Unit = {
        Description = "thide, hides the taskbar";
        After = [ "tray.target" ];
        # A new thide is installed over the running one: restart onto it.
        X-Restart-Triggers = [ pkgs.thide ];
      };
      Service = {
        ExecStart = ''"${exe}"'';
        ExecStop = ''"${exe}" stop'';
      };
      Install.WantedBy = [ "tray.target" ];
    };
}
