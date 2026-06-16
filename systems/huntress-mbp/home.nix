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

  home.packages = with pkgs; [
    discord
    github-cli
    awscli2
    ssm-session-manager-plugin
    aws-vault
    colima
    docker
    raycast
    kubernetes-helm
    kubectl
    azure-cli
    kubelogin
    nodejs
    circleci-cli
    shortcut-cli
    poppler-utils
  ];

  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "i-*" = {
        proxyCommand = "sh -c \"aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --region us-east-1\"";
      };
    };
  };

  programs.rbenv.enable = true;

  # This fails in MacOS
  programs.nixvim.plugins.lsp.servers.mesonlsp.enable = lib.mkForce false;

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
