{ nix-colors, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
{
  # As with system configuration, it's all under `stewos`
  stewos = {
    # Configure the desktop environment (hyprland) and associated services
    desktop = {
      enable = true;
      modifier = "SUPER";

      # Configure your preferred wallpaper.
      # The default here is a fun rendering of a black hole.
      wallpaper = pkgs.fetchurl {
        url = "https://i.redd.it/uhmtqleyl2sd1.jpeg";
        sha256 = "sha256-Kh1bYNBodOBN4PDnuO1ko4rB12xAOOdSNYUnDFb0z+0=";
      };

      # This is optional, but useful. If not specified, Hyprland decides
      # our monitor layout, and resolutions. This will configure monitors
      # by their unique names and a consistent resolution and scaling
      # factor. It will automatically calculate their relative positions
      # based on the selected resolution, and scaling factor so you don't
      # have to do math. Just put their names in the `orderedNames` array
      # in the order you want them arranged (left to right).
      monitors =
        let
          # Unique names of monitors in the horizontal order they are
          # configured in the real world. See `hyprctl monitors` at
          # runtime to find the unique names of your monitors.
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

    # Configure supported StewOS applications
    git.enable = true;
    alacritty.enable = true;
    bat.enable = true;
    firefox.enable = true;
    eza.enable = true;
    zsh.enable = true;
    neovim.enable = true;
    zoxide.enable = true;
    direnv.enable = true;
  };

  # Since we have the system config auto-login in configuration.nix, we can use this
  # to automatically lock our session on the first startup of Hyprland. I like
  # hyprlock better than any locker, and I run a single-user machine, so this works
  # nicely. This is purely preference.
  xdg.configFile."hypr/config.d/99-autolock.conf".text = ''
    exec-once = ${lib.getExe config.programs.hyprlock.package} --immediate --quiet --no-fade-in
  '';

  # This is used for configuring various applications
  colorScheme = nix-colors.colorSchems.catppuccin-mocha;
}
