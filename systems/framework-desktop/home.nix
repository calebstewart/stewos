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
    pkgs.spotify
  ];

  stewos = {
    desktop = {
      enable = true;
      modifier = "SUPER";

      wallpaper = pkgs.fetchurl {
        url = "https://i.redd.it/uhmtqleyl2sd1.jpeg";
        sha256 = "sha256-Kh1bYNBodOBN4PDnuO1ko4rB12xAOOdSNYUnDFb0z+0=";
      };

      # wallpaper = pkgs.fetchurl {
      #   url = "https://lh3.googleusercontent.com/pw/AP1GczM8Zlkuq2_ccOHyjjfHodRhXjmujKWSwpy8_XOEMiOxvBOo2ZYNT4mN_LwiTHBWrvlcuU-db7uTTnhU6zODkIW3f85L2XErIfWNkuBru9Ws5sFyIos5nBPN_JWuFMCX9-j5gDnl6cXsUkBUR2pYdgfEAQ=w3468-h1951-s-no?authuser=0";
      #   hash = "sha256-uy0TQ+K15h6IMmv3Tbd15+nM3XR/rD/1GYZQxQUoRjQ=";
      #   # url = "https://lh3.googleusercontent.com/pw/AP1GczMFuTffAIDMFEND7odg-nmIPaEgPIPhGwv94oxhpFFe5CN4QunlA77wz4raxgTZ68Uje2SPmBhR1A5iluCevPDUSsueXyViocCrZUDVPYKAeazOJGgTYoGgH-6CqRohmh42vi7giZoUiAep4XHn8BjULg=w3591-h2020-s-no";
      #   # hash = "sha256-gAAV3OkG66ZonBjV0brY/Br6vsxIbws+lQRqyUN35Mg=";
      # };

      monitors =
        let
          # Unique names of monitors in the horizontal order they are
          # configured in the real world.
          orderedNames = [
            "Dell Inc. DELL U2723QE 55L01P3"
            "Dell Inc. DELL U2723QE HXJ01P3"
          ];

          # Resolution used for all monitors
          resolution = {
            width = 3840;
            height = 2160;
          };

          # Scale used for all monitors
          scale = 1.5;
        in
        # Configure all monitors in orderedNames and set their X positions
        # appropriately based on their index in the ordered list, the
        # resolution width and the scaling factor.
        lib.imap0 (i: description: {
          inherit resolution description scale;
          position.x = (builtins.floor (resolution.width / scale)) * i;
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
  };

  xdg.configFile."hypr/config.d/99-autolock.conf".text = ''
    exec-once = ${lib.getExe config.programs.hyprlock.package} --immediate --quiet --no-fade-in
  '';

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
