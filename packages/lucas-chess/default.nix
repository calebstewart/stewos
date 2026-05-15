{
  lib,
  stdenv,
  fetchurl,
  p7zip,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  zlib,
  glibc,
  libGL,
  libxkbcommon,
  qt5,
  xorg,
  # Optional dependencies for additional features
  wayland,
  hidapi,
  bluez,
  numactl,
  # XKB configuration for Wayland
  xkeyboard_config,
}:
stdenv.mkDerivation rec {
  pname = "lucas-chess";
  version = "R2.21-FP19a";

  src = fetchurl {
    url = "https://github.com/lukasmonk/lucaschessR2/releases/download/${version}/LucasChessR2_21-FP19LINUX.7z";
    hash = "sha256-XVdoMeosxvRDFY7AQukHCJcpdz07lX2qJH5uqueBkfc=";
  };

  nativeBuildInputs = [
    p7zip
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    zlib
    glibc
    stdenv.cc.cc.lib
    libGL
    libxkbcommon
    xorg.libX11
    xorg.libxcb
    # Qt libraries
    qt5.qtbase
    qt5.qtwayland
    qt5.qtdeclarative
    qt5.qtvirtualkeyboard
    # Wayland support
    wayland
    # Digital chess board support
    hidapi
    bluez
    # NUMA optimization for engines
    numactl
  ];

  # We handle Qt wrapping manually via makeWrapper
  dontWrapQtApps = true;

  # Ignore unavailable optional dependencies:
  # - CUDA libs: requires unfree license and NVIDIA GPU
  # - Qt5Pas: Pascal bindings not packaged in nixpkgs (for some digital boards)
  # - Qt5Pdf: would require heavy qtwebengine dependency
  autoPatchelfIgnoreMissingDeps = [
    "libcuda.so.1"
    "libcudart.so.*"
    "libnvinfer.so.*"
    "libQt5Pas.so.1"
    "libQt5Pdf.so.5"
  ];

  unpackPhase = ''
    runHook preUnpack
    7z x $src
    runHook postUnpack
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Install application
    mkdir -p $out/share/lucas-chess
    cp -r LucasChessR/* $out/share/lucas-chess/

    # Install icon (if available)
    mkdir -p $out/share/icons/hicolor/256x256/apps
    if [ -f $out/share/lucas-chess/bin/Resources/LucasR.ico ]; then
      cp $out/share/lucas-chess/bin/Resources/LucasR.ico $out/share/icons/hicolor/256x256/apps/lucas-chess.ico
    elif [ -f $out/share/lucas-chess/bin/Resources/LucasR.png ]; then
      cp $out/share/lucas-chess/bin/Resources/LucasR.png $out/share/icons/hicolor/256x256/apps/lucas-chess.png
    fi

    # Create wrapper script that sets up a writable runtime directory
    # The application expects to write to bin/bug.log and UserData/
    mkdir -p $out/bin
    cat > $out/bin/lucas-chess << 'WRAPPER'
#!/usr/bin/env bash
set -e

# Create runtime directory structure in user's home
LUCAS_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/lucas-chess"
mkdir -p "$LUCAS_HOME/bin" "$LUCAS_HOME/UserData"

# Symlink read-only resources at top level
for item in Resources dic_files.txt LICENSE readme.md requirements.txt setup_linux.sh version.txt; do
    if [ ! -e "$LUCAS_HOME/$item" ]; then
        ln -sf "@out@/share/lucas-chess/$item" "$LUCAS_HOME/$item"
    fi
done

# Symlink read-only contents of bin directory (except writable files)
for item in "@out@/share/lucas-chess/bin/"*; do
    name=$(basename "$item")
    # Skip files that need to be writable
    if [ "$name" = "bug.log" ]; then
        continue
    fi
    if [ ! -e "$LUCAS_HOME/bin/$name" ]; then
        ln -sf "$item" "$LUCAS_HOME/bin/$name"
    fi
done

# Create writable bug.log if it doesn't exist
touch "$LUCAS_HOME/bin/bug.log"

# Change to runtime directory and execute
cd "$LUCAS_HOME/bin"
export QT_LOGGING_RULES='*=false'
export XKB_CONFIG_ROOT='@xkb@/share/X11/xkb'
exec ./LucasR "$@"
WRAPPER
    chmod +x $out/bin/lucas-chess
    substituteInPlace $out/bin/lucas-chess \
      --replace-fail "@out@" "$out" \
      --replace-fail "@xkb@" "${xkeyboard_config}"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "lucas-chess";
      exec = "lucas-chess";
      icon = "lucas-chess";
      desktopName = "Lucas Chess R2";
      comment = "Chess training application with 71 engines";
      categories = [
        "Game"
        "BoardGame"
      ];
    })
  ];

  meta = {
    description = "Chess training application with 71 engines";
    homepage = "https://lucaschess.pythonanywhere.com/home";
    license = lib.licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "lucas-chess";
    maintainers = [ ];
  };
}
