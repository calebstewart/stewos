{nix-colors, lib, pkgs, ...}: {
  stewos = {
    # Configure Graphical Desktop Settings
    desktop = rec {
      enable = true;
      wallpaper = ./../../images/spaceman.jpg;
      modifier = "ALT";

      # Construct a linear left-to-right monitor configuration with identical
      # resolutions and scaling factors.
      monitors = let
        # Monitor names/descriptions in left-to-right order
        orderedNames = ["Dell Inc. DELL U2723QE HXJ01P3" "Dell Inc. DELL U2723QE 55L01P3" "Dell Inc. DELL U2718Q 4K8X7974188L"];

        # Resolution to be applied to each monitor
        resolution = { width = 3840; height = 2160; };
      in lib.imap0 (i: description: {
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

    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
      aliases.huntress.email = "caleb.stewart@huntresslabs.com";
    };
  };

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
