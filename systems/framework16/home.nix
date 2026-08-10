{ nix-colors, ... }:
{
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
    };

    git.enable = true;
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

  wayland.windowManager.hyprland.settings.device = {
    name = "framework-laptop-16-keyboard-module---ansi-keyboard";
    kb_options = "caps:swapescape";
  };

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
