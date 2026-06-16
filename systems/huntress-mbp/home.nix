{ nix-colors, stewos, ... }:
{ pkgs, lib, ... }:
{
  stewos = {
    # Setup our desktop
    desktop = {
      enable = true;
      modifier = "ALT";

      wallpaper = pkgs.fetchurl {
        url = "https://images-assets.nasa.gov/image/art002e000191/art002e000191~large.jpg";
        sha256 = "sha256-SQfQAhWvyUM7X6u+fW89TjR7eYaOSXIS9XzVaXsQIIc=";
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
      ssm-session-manager-plugin
      aws-vault
      colima
      docker
      raycast
    ]
    ++ (with stewos.packages.${pkgs.system}; [
      # hunt-cli
    ]);

  programs.rbenv.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
  };

  # This fails in MacOS
  programs.nixvim.plugins.lsp.servers.mesonlsp.enable = lib.mkForce false;

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
