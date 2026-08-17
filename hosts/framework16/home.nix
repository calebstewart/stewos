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

      # The built-in keyboard enumerates as its own input device, which the
      # session-wide keyboard settings do not reach.
      keyboards."framework-laptop-16-keyboard-module---ansi-keyboard".capsLockEscape = true;
    };

    update-manager.enable = true;

    git.enable = true;
    delta.enable = true;
    alacritty.enable = true;
    bat.enable = true;
    firefox.enable = true;
    eza.enable = true;
    rofi.enable = true;
    zsh.enable = true;
    neovim.enable = true;
    zoxide.enable = true;
    direnv.enable = true;
  };

  home.packages = with pkgs; [
    discord
    signal-desktop
    btop
  ];

  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;
}
