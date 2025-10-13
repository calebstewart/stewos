{stewos, ...}:
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
  };

  home.packages = with pkgs; [
    discord
    github-cli
  ] ++ (with stewos.packages.${pkgs.system}; [
    hunt-cli
  ]);

  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;
  programs.rbenv.enable = true;
}
