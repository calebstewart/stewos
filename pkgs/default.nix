# The StewOS package scope.
#
# Every package lives on a line below -- nothing is discovered by scanning the
# directory, so this file is the complete list of what StewOS builds.
#
# These are ordinary callPackage derivations: each takes its dependencies as
# arguments and none of them reference flake inputs. Anything that has to come
# from a flake input (an unpacked source tree, a colour scheme) is injected into
# the scope by overlays/default.nix and resolved here by argument name, which is
# what keeps this file buildable against a plain nixpkgs.
self: {
  # Builders. These are functions rather than derivations, so they are filtered
  # out of the flake's "packages" output (see flake.nix).
  mkRofiConfig = self.callPackage ./rofi/mk-config.nix { };
  mkRofiTheme = self.callPackage ./rofi/mk-theme.nix { };

  # Packages.
  gh-actions-language-server = self.callPackage ./gh-actions-language-server { };
  hyprpolkitagent = self.callPackage ./hyprpolkitagent { };
  hyprqt6engine = self.callPackage ./hyprqt6engine { };
  lucas-chess = self.callPackage ./lucas-chess { };
  macfetch = self.callPackage ./macfetch { };
  shortcut-cli = self.callPackage ./shortcut-cli { };
  update-manager = self.callPackage ./update-manager { };
  update-manager-icons = self.callPackage ./update-manager-icons { };
  wl-gen-uuid = self.callPackage ./wl-gen-uuid { };

  # Rofi theme and script modes.
  rofi-theme = self.callPackage ./rofi/theme.nix { };
  rofi-hyprpower = self.callPackage ./rofi/scripts/hyprpower { };
  rofi-libvirt = self.callPackage ./rofi/scripts/libvirt { };
}
