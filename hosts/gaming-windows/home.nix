# Windows 11 desktop: the *home* configuration -- this user, applied as the
# user, never elevated. The machine's half is configuration.nix. See mkHome in
# flake.nix.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  winpkgs = inputs.winpkgs;
in {
  home.packages = with pkgs; [
    git
    ripgrep
    nerd-fonts.jetbrains-mono
    thide # hides the taskbar; alt + b brings it back
  ];

  # Install packages explicitly from winget
  winget.packages = [ "Fastfetch-cli.Fastfetch" ];

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
      # thide in tray mode hides the taskbar as it starts; alt + b toggles it.
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
    settings.profiles.defaults.font.face = "JetBrainsMono Nerd Font Mono";
    settings.copyOnSelect = true;
    base16 = { palette = config.colorScheme.palette; name = "Catppuccin Mocha"; };
  };

  programs.whkd = {
    enable = true;
    shell = "pwsh";                  # your current file says powershell; pwsh is on the machine
    pause = "alt + shift + p";       # game mode: silences every other binding ...
    pauseHook = "komorebic toggle-pause";  # ... and pauses tiling; again to resume both
    
    keybindings =
      let
        # Workspaces by position on the *focused* monitor: keys 1-5 are
        # komorebi's workspace indices 0-4, whichever monitor has focus.
        keys = [ "1" "2" "3" "4" "5" ];

        # one binding per key: "<modifiers> + <key>" -> "komorebic <command> <index>"
        perWorkspace =
          modifiers: command:
          lib.listToAttrs (
            lib.imap0 (index: key: {
              name = "${modifiers} + ${key}";
              value = "komorebic ${command} ${toString index}";
            }) keys
          );
      in
      # alt + N          focus workspace N on this monitor
      perWorkspace "alt" "focus-workspace"
      # alt + shift + N  move the focused window to N and follow it
      // perWorkspace "alt + shift" "move-to-workspace"
      # alt + ctrl + N   send the focused window to N and stay put
      // perWorkspace "alt + ctrl" "send-to-workspace"
      // {
        # cycle through workspaces on the current monitor
        "alt + oem_comma" = "komorebic cycle-workspace previous";
        "alt + oem_period" = "komorebic cycle-workspace next";
        "alt + shift + oem_comma" = "komorebic cycle-move-to-workspace previous";
        "alt + shift + oem_period" = "komorebic cycle-move-to-workspace next";

        # back to wherever you were
        "alt + tab" = "komorebic focus-last-workspace";
        "alt + shift + tab" = "komorebic move-to-last-workspace";

        # the other monitor
        "alt + w" = "komorebic cycle-monitor next";
        "alt + shift + w" = "komorebic cycle-move-to-monitor next";

        # whkd reads whkdrc once: after a `winpkgs home switch`, press this.
        "alt + o" = "taskkill /f /im whkd.exe; Start-Process whkd -WindowStyle hidden";
        "alt + shift + o" = "komorebic reload-configuration";
        "alt + i" = "komorebic toggle-shortcuts";

        # focus a window if open, else launch ($wshell is whkd's WScript.Shell)
        "alt + return" = ''Start-Process "C:\Program Files\Alacritty\alacritty.exe" -WorkingDirectory $Env:USERPROFILE'';

        "alt + d" = config.programs.flow-launcher.showCommand;
        "alt + shift + r" = "Start-Process ms-screenclip:";   # rectangular screen capture, as Print Screen does
        "alt + b" = ''& "$Env:LOCALAPPDATA\Programs\thide\thide.exe" toggle'';   # show or hide the taskbar
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
      };
  };

  # Keyboard launcher; whkd summons it on alt + d (see keybindings).
  programs.flow-launcher = {
    enable = true;
    base16 = {
      palette = config.colorScheme.palette;
      name = "Catppuccin Mocha";
    };
  };

  # Focus follows the mouse; masir only focuses windows komorebi manages.
  programs.masir.enable = true;

  programs.gh.enable = true;

  programs.komorebi = {
    enable = true;

    base16.palette = config.colorScheme.palette;

    # The community application rules (a pinned flake input): what makes the
    # Snipping Tool overlay, installers and tray apps float or be ignored.
    applications = "${inputs.komorebi-asc}/applications.json";

    settings = {
      # Focus follows the mouse instead (programs.masir, above).
      mouse_follows_focus = false;
      window_hiding_behaviour = "Cloak";
      cross_monitor_move_behaviour = "Insert";

      default_workspace_padding = 5;
      default_container_padding = 5;

      border = true;
      border_width = 1;
      border_offset = -1;

      monitors =
        let
          bsp = name: {
            inherit name;
            layout = "BSP";
          };
        in
        [
          { workspaces = map bsp [ "1" "2" "3" "4" "5" ]; }
          { workspaces = map bsp [ "6" "7" "8" "9" "0" ]; }
        ];

      layered_applications = [
        {
          kind = "Exe";
          id = "claude.exe";
          matching_strategy = "Equals";
        }
      ];
    };

    bar = {
      enable = true;

      # One bar per monitor (komorebi monitor indices), each from `settings` below.
      monitors = {
        "0" = { };
        "1" = { };
      };

      settings = {
        font_family = "JetBrains Mono";

        left_widgets = [
          {
            Komorebi = {
              workspaces = {
                enable = true;
                hide_empty_workspaces = true;
              };
              layout.enable = false;
              focused_window = {
                enable = true;
                show_icon = true;
              };
            };
          }
        ];

        right_widgets = [
          { Update.enable = true; }
          {
            Date = {
              enable = true;
              format = "DayDateMonthYear";
            };
          }
          {
            Time = {
              enable = true;
              format = "TwentyFourHour";
            };
          }
        ];
      };
    };
  };
}
