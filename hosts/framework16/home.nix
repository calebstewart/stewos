{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  stewos = {
    desktop = {
      enable = true;
      modifier = "ALT";
      startLocked = true;

      monitors = [
        {
          description = "BOE NE160QDM-NZ6";
          scale = 1.2;
        }
      ];

      # The built-in keyboard enumerates as its own input device, which the
      # session-wide keyboard settings do not reach.
      keyboards."framework-laptop-16-keyboard-module---ansi-keyboard".capsLockEscape = true;
    };

    git.enable = true;
    delta.enable = true;
    alacritty.enable = true;
    bat.enable = true;
    firefox.enable = false;
    eza.enable = true;
    rofi.enable = true;
    zsh.enable = true;
    neovim.enable = true;
    zoxide.enable = true;
    direnv.enable = true;
  };

  services.nixos-update-manager.enable = true;

  home.packages =
    (with pkgs; [
      discord
      signal-desktop
      btop
      opencode
    ])
    ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      claude-desktop
    ]);

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "x-scheme-handler/discord" = "discord.desktop";
      "x-scheme-handler/sgnl" = "signal.desktop";
      "x-scheme-handler/signalcaptcha" = "signal.desktop";
      "x-scheme-handler/claude" = "claude-desktop.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  # Setup Chrome
  programs.chromium = {
    enable = true;
    package = pkgs.chromium.override {
      enableWideVine = true;

      commandLineArgs = [
        "--ozone-platform-hint=auto"
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
      ];
    };

    extensions =
      let
        lastpass.id = "hdokiejnpimakedhajhdlcegeplioahd";
      in
      [
        lastpass
      ];
  };
}
