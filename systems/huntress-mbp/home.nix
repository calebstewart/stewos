{nix-colors, stewos, ...}:
{pkgs, lib, ...}: {
  stewos = {
    # Setup user properties
    user = {
      fullName = "Caleb Stewart";
      email = "caleb.stewart94@gmail.com";
      aliases.huntress.email = "caleb.stewart@huntresslabs.com";
    };

    # Graphical User Interface (GUI)
    firefox.enable = false;
    alacritty.enable = true;
    aerospace.enable = true;

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
    aws-vault
    colima
    docker

    # On linux, these are part of the desktop module, but that isn't used
    # on Darwin. We should probably make them their own module...
    jetbrains-mono
    roboto
    openmoji-color
    nerd-fonts.jetbrains-mono
  ] ++ (with stewos.packages.${pkgs.system}; [
    # hunt-cli
  ]);

  programs.ssh.enable = true;
  programs.rbenv.enable = true;

  colorScheme = nix-colors.colorSchemes.catppuccin-mocha;
}
