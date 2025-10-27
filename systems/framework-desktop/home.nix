{ nix-colors, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
{
  home.packages = [
    pkgs.discord
    pkgs.gimp
    pkgs.signal-desktop
  ];

  stewos = {
    desktop = {
      enable = true;
      modifier = "SUPER";

      wallpaper = pkgs.fetchurl {
        url = "https://lh3.googleusercontent.com/pw/AP1GczMFuTffAIDMFEND7odg-nmIPaEgPIPhGwv94oxhpFFe5CN4QunlA77wz4raxgTZ68Uje2SPmBhR1A5iluCevPDUSsueXyViocCrZUDVPYKAeazOJGgTYoGgH-6CqRohmh42vi7giZoUiAep4XHn8BjULg=w3591-h2020-s-no";
        hash = "sha256-gAAV3OkG66ZonBjV0brY/Br6vsxIbws+lQRqyUN35Mg=";
      };

      monitors =
        let
          orderedNames = [
            "Dell Inc. DELL U2723QE 55L01P3"
            "Dell Inc. DELL U2723QE HXJ01P3"
          ];
          resolution = {
            width = 3840;
            height = 2160;
          };
        in
        lib.imap0 (i: description: {
          inherit resolution description;
          position.x = resolution.width * i;
          scale = 1.0;
        }) orderedNames;
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

    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
    };
  };

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
