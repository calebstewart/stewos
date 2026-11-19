# The caelestia configuration as it is run on Windows: upstream's QML, with the
# files under ./windows laid over it.
#
# Caelestia's QML runs unchanged under the Windows build of Quickshell
# (pkgs/quickshell-windows), which provides the Quickshell modules it imports.
# Two services are the exception. They do their work by running Linux tools --
# ddcutil and brightnessctl for brightness, nmcli for the network -- so no
# module underneath can stand in for them, and each is replaced whole by a file
# that offers the same members and asks Quickshell's Windows backends instead.
# Replacing the file, not patching it, keeps this free of merge conflicts; what
# it cannot catch is upstream starting to use a member a replacement lacks,
# which shows as a QML warning at run time.
#
# This is only QML and assets. The C++ plugin the QML imports is built into
# the Quickshell bundle, against the same Qt, so the two have to be the same
# caelestia revision: the desktop's Windows backend asserts that `rev` here is
# the one the bundle was built from.
{
  lib,
  runCommand,
  caelestia-shell-src,
}:
runCommand "caelestia-shell-windows-${caelestia-shell-src.shortRev or "source"}"
  {
    src = caelestia-shell-src;
    replacements = ./windows;

    passthru.rev = caelestia-shell-src.rev or null;

    meta = {
      description = "The caelestia shell's QML configuration, with its Linux-only services replaced for Windows";
      homepage = "https://github.com/caelestia-dots/shell";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.all;
    };
  }
  ''
    mkdir -p $out
    cp -r $src/. $out/
    chmod -R u+w $out

    # The plugin's source, the Linux packaging and the repository's own files
    # are not part of the configuration.
    rm -rf $out/.github $out/.vscode $out/plugin $out/nix $out/extras $out/scripts
    rm -f $out/flake.nix $out/flake.lock $out/CMakeLists.txt $out/.envrc \
      $out/.clang-format $out/.clang-tidy $out/.editorconfig $out/.gitignore

    # A replacement for a file upstream no longer has replaces nothing: it
    # would be an extra file, and whatever took the old one's place would run
    # unreplaced.
    (cd $replacements && find . -type f) | while IFS= read -r file; do
      if [ ! -e "$src/$file" ]; then
        echo "pkgs/caelestia-shell/windows/$file replaces a file caelestia no longer has" >&2
        exit 1
      fi
    done
    cp -r $replacements/. $out/
    chmod -R u+w $out

    # winpkgs refuses to install a file that names the store.
    if grep -rl ${builtins.storeDir}/ $out; then
      echo "the files above mention ${builtins.storeDir}/; winpkgs would refuse them" >&2
      exit 1
    fi
  ''
