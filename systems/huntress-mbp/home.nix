{ nix-colors, stewos, ... }:
{ pkgs, lib, ... }:
{
  stewos = {
    # Setup user properties
    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
      aliases.huntress.email = "caleb.stewart@huntresslabs.com";
    };

    # Setup our desktop
    desktop = {
      enable = true;
      modifier = "ALT";

      wallpaper = pkgs.fetchurl {
        url = "https://i.redd.it/uhmtqleyl2sd1.jpeg";
        sha256 = "sha256-Kh1bYNBodOBN4PDnuO1ko4rB12xAOOdSNYUnDFb0z+0=";
      };
    };

    # Graphical User Interface (GUI)
    firefox.enable = false;
    alacritty.enable = true;

    # Command Line Interface (CLI)
    neovim.enable = true;
    zsh.enable = true;
    git.enable = true;
    zoxide.enable = true;
    bat.enable = true;
    eza.enable = true;
    direnv.enable = true;
  };

  home.packages =
    with pkgs;
    [
      discord
      github-cli
      awscli2
      aws-vault
      colima
      docker
    ]
    ++ (with stewos.packages.${pkgs.system}; [
      # hunt-cli
    ]);

  programs.ssh.enable = true;
  programs.rbenv.enable = true;

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
