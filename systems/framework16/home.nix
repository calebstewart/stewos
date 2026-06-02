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

  # Lock caelestia on start
  systemd.user.services.caelestia.Service.ExecStartPost = [
    (lib.escapeShellArgs [
      (lib.getExe config.programs.caelestia.cli.package)
      "shell"
      "lock"
      "lock"
    ])
  ];

  xdg.configFile."hypr/config.d/99-framework-keyboard.conf".text = ''
    device {
      name = framework-laptop-16-keyboard-module---ansi-keyboard
      kb_options = caps:swapescape
    }
  '';

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
