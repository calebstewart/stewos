{nix-colors, ...}:
{lib, pkgs, ...}: {
  stewos = {
    desktop = {
      enable = true;
      wallpaper = ./../../images/spaceman.jpg;
      modifier = "SUPER";

      monitors = let
        orderedNames = ["Dell Inc. DELL U2723QE 55L01P3" "Dell Inc. DELL U2723QE HXJ01P3"];
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
    direnv.enable = true;

    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
    };
  };

  home.packages = [pkgs.discord];

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
