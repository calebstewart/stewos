# StewOS - NixOS Single-User System Flake
This flake template provides a single NixOS system configuration output
and a Home Manager configuration output. Both outputs are intended for
the same system and automatically use StewOS.

Before this flake will work, you must first initialize a git repository
and add the files to `git`. You must also copy `hardware-configuration.nix`
to this directory and add it to `git` as well. This file should have been
generated for you when you installed/setup your base NixOS system.

You should also set your user name, full name, and email address in
`flake.nix`. This is used to configure your user information and certain
applications such as `git`.

StewOS sets up `nh` for managing your NixOS and Home Manager configurations
and expects that your system configuration flake is stored in `~/git/stewos`.

For more information, please visit the StewOS GitHub: https://github.com/calebstewart/stewos
