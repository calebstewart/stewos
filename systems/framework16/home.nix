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

  home.file.".wayland-session" = {
    text = ''
      exec ${lib.getExe config.wayland.windowManager.hyprland.package} >/dev/null 2>/dev/null
    '';

    executable = true;
  };

  xdg.configFile."hypr/config.d/99-autolock.conf".text = ''
    exec-once = ${lib.getExe config.programs.hyprlock.package} --immediate --quiet --no-fade-in
  '';

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
