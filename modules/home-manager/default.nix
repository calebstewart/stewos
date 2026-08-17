# Every StewOS home-manager module.
#
# As with the NixOS tree, each module is inert until enabled, and the list is
# explicit so that it can be read and grepped without evaluating anything.
{ inputs, ... }:
{
  imports = [
    inputs.nix-colors.homeManagerModules.default
    inputs.stylix.homeModules.stylix

    ../common/user.nix

    ./alacritty.nix
    ./bat.nix
    ./delta.nix
    ./desktop
    ./direnv.nix
    ./embermug-tray.nix
    ./eza.nix
    ./firefox.nix
    ./ghostty.nix
    ./git.nix
    ./neovim.nix
    ./rofi.nix
    ./update-manager.nix
    ./zoxide.nix
    ./zsh.nix
  ];

  home.stateVersion = "25.05";
}
