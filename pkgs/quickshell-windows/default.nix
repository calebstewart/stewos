# Quickshell for Windows, as the prebuilt bundle the fork's CI publishes
# (github:calebstewart/quickshell, branch `windows`, ci/windows/bundle.sh):
# quickshell.exe with Qt and every other DLL beside it, and a qml/ directory
# that also holds the caelestia shell's C++ plugin and M3Shapes.
#
# A binary, not a build. Cross-compiling Qt Quick, its shader tools and C++/WinRT
# for MinGW from nixpkgs is a project of its own, and MSYS2 already carries
# all of it, so the fork builds there and this pins the result. Nothing in it
# comes from the store, which is what lets winpkgs copy it onto the machine.
#
# The plugin inside is caelestia's, built against this bundle's Qt, and it has
# to be the revision of the QML it is run with (pkgs/caelestia-shell/
# windows.nix). `caelestiaRev` says which that is, and the fetch fails if the
# bundle's own manifest disagrees. Moving the caelestia input therefore means
# a new bundle: bump ci/windows/versions.env in the fork, tag, and update
# `version`, `hash` and `caelestiaRev` here.
{
  lib,
  fetchzip,
}:
let
  version = "2026.11.17.2";
  caelestiaRev = "fd630ffedd45eb31817e9a1726a0f567e79f65e2";
in
fetchzip {
  name = "quickshell-windows-${version}";
  url = "https://github.com/calebstewart/quickshell/releases/download/windows-${version}/quickshell-windows-x86_64.zip";
  hash = "sha256-oFVk7She41qunchCAV+KUwq8auwjSFssOqyLhMPRJME=";

  postFetch = ''
    if ! grep -qF '"caelestia": "${caelestiaRev}"' $out/manifest.json; then
      echo "the bundle's caelestia plugin is not revision ${caelestiaRev}:" >&2
      grep -F '"caelestia"' $out/manifest.json >&2
      exit 1
    fi
  '';

  passthru = { inherit version caelestiaRev; };

  meta = {
    description = "Quickshell for Windows, bundled with Qt, the caelestia shell's plugin and M3Shapes";
    homepage = "https://github.com/calebstewart/quickshell";
    license = with lib.licenses; [
      lgpl3Only
      gpl3Only
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.all;
    mainProgram = "quickshell";
  };
}
