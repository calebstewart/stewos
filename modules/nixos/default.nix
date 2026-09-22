# Every StewOS NixOS module.
#
# Importing this gives you all of the options; each module stays inert until you
# set its "enable" flag, so this is cheap to import wholesale. The exception is
# base.nix, which applies defaults and can be switched off with
# stewos.base.enable = false.
#
# Modules are listed explicitly rather than discovered by scanning the
# directory: adding a file here is one line, and in exchange every import is
# greppable and the set of modules is visible without evaluating anything.
{ inputs, ... }:
{
  imports = [
    inputs.stylix.nixosModules.stylix

    ./audio.nix
    ./autologin.nix
    ./base.nix
    ./containers.nix
    ./desktop-services.nix
    ./greeter.nix
    ./looking-glass
    ./networking.nix
    ./security.nix
    ./sshd.nix
    ./user.nix
    ./virtualisation.nix
    ./zsa
  ];
}
