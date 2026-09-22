# Pure helper functions.
#
# Nothing in here depends on flake inputs -- it takes a nixpkgs lib and returns
# plain functions -- so it can be imported from the overlay, from a module, or
# from a REPL without dragging the flake along.
{ lib }:
{
  desktop = import ./desktop.nix { inherit lib; };
  docs = import ./docs { inherit lib; };
  rasi = import ./rasi { inherit lib; };
  rofi = import ./rofi.nix { inherit lib; };
}
