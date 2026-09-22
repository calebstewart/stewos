# The upstream hyprqt6engine (from the flake input, injected into the scope by
# overlays/default.nix) rebuilt against the stdenv the Qt stack itself uses.
#
# Upstream's overlay pins "stdenv = gcc16Stdenv", matching the rest of the Hypr
# ecosystem. That is correct for a Hyprland application -- a standalone process
# resolves libstdc++ through its own RPATH -- but wrong for a Qt platform theme,
# which is dlopen'd into a host that already has a libstdc++.so.6 mapped. The
# loader matches on SONAME, so the plugin gets the *host's* copy regardless of
# its own RPATH. nixpkgs builds every Qt app with gcc 15 while the Hypr packages
# are on gcc 16, so the plugin asks for a symbol version that is not there:
#
#   libhyprqt6engine.so cannot load: .../gcc-15.3.0-lib/lib/libstdc++.so.6:
#   version `GLIBCXX_3.4.36' not found
#
# The failure is silent unless QT_DEBUG_PLUGINS is set. Qt just ends up with no
# platform theme, so QIcon::themeName() is empty and every QIcon::fromTheme
# lookup returns null -- which surfaces only as missing icons in Qt apps (the
# tray, notification popups, anything quickshell draws by icon name).
#
# hyprlang and hyprutils export the same symbol version, and nixpkgs builds both
# with gcc16Stdenv too, so they have to be rebuilt alongside it. All three
# compile cleanly under gcc 15. Drop this file once upstream builds the plugin
# against the Qt stdenv; see ./upstream-issue.md.
#
# The upstream package only exists for Linux systems, so the injected value is
# null elsewhere; flake.nix's packages filter drops the null.
{
  hyprqt6engine-upstream,
  hyprlang,
  hyprutils,
  qt6Packages,
}:
if hyprqt6engine-upstream == null then
  null
else
  let
    # Passing qt6Packages as well as the stdenv is deliberate: the plugin has to
    # be built against the exact qtbase the apps loading it were built against,
    # which is the whole point of the rebuild.
    qtStdenv = qt6Packages.qtbase.stdenv;

    # nixpkgs takes the stdenv for these two under the argument name
    # "gcc16Stdenv", so that -- not "stdenv" -- is the override key.
    qtHyprutils = hyprutils.override { gcc16Stdenv = qtStdenv; };
    qtHyprlang = hyprlang.override {
      gcc16Stdenv = qtStdenv;
      hyprutils = qtHyprutils;
    };
  in
  hyprqt6engine-upstream.override {
    stdenv = qtStdenv;
    hyprlang = qtHyprlang;
    hyprutils = qtHyprutils;
    inherit qt6Packages;
  }
