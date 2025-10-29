{ nix-colors, ... }:
{ pkgs, ... }:
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

    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
    };
  };

  home.packages = with pkgs; [
    discord
    signal-desktop
    btop
  ];

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
