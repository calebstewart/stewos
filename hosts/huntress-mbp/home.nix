{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  stewos = {
    # Setup our desktop
    desktop = {
      enable = true;
      modifier = "ALT";
      terminal = pkgs.ghostty-bin;

      capsLockEscape = true;

      # Put the "ALT" prefix above on the key this keyboard labels Command.
      swapCommandAlt = true;

      # Ghostty is single-instance on macOS, so the stock "terminal" action's
      # `open -na` cannot open a window; ask the running app for one instead.
      bindings.terminal = {
        action = null;
        command.package = pkgs.writeShellApplication {
          name = "ghostty-new-window";
          text = ''
            exec /usr/bin/osascript -e 'tell application "Ghostty"
              new window
            end tell'
          '';
        };
      };

      wallpaper = pkgs.fetchurl {
        url = "https://images-assets.nasa.gov/image/art002e000191/art002e000191~large.jpg";
        sha256 = "sha256-SQfQAhWvyUM7X6u+fW89TjR7eYaOSXIS9XzVaXsQIIc=";
      };
    };

    # Graphical User Interface (GUI)
    firefox.enable = false;
    ghostty.enable = true;

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
    github-cli
    awscli2
    ssm-session-manager-plugin
    aws-vault
    docker
    raycast
    kubernetes-helm
    kubectl
    azure-cli
    kubelogin
    nodejs
    circleci-cli
    poppler-utils
    stewos.shortcut-cli
    stewos.macfetch
  ];

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.rd/bin"
  ];

  programs.nixcord = {
    enable = true;
    discord.vencord.enable = true;

    config = {
      useQuickCss = true;
      frameless = true;
      plugins = { };
    };
  };

  # Add rustup environment config
  programs.zsh.initContent = ''
    source "$HOME/.cargo/env"
  '';

  # Home-manager owns ~/.zprofile, so Homebrew's shell environment (PATH,
  # MANPATH, HOMEBREW_*) has to be wired up here rather than by `brew`
  # appending to the file itself.
  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  '';

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # Reach EC2 instances by instance ID through SSM rather than by address.
    # Attribute names are Host patterns and keys are OpenSSH directive names.
    settings."i-*".ProxyCommand =
      ''sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --region us-east-1"'';
  };

  # This host pairs home-manager master with the nixpkgs-*-darwin release
  # branch, which trips home-manager's release check. The skew is deliberate
  # (see CLAUDE.md known failure modes), so silence the warning here rather
  # than pinning home-manager for every host.
  home.enableNixpkgsReleaseCheck = false;

  programs.rbenv.enable = true;

  # This fails in MacOS
  programs.nixvim.plugins.lsp.servers.mesonlsp.enable = lib.mkForce false;

  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;
}
