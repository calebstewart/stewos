{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  dbus,
  git,
  nix,
  update-manager-icons,
}:
rustPlatform.buildRustPackage {
  pname = "stewos-update-manager";
  version = "0.1.0";

  # An explicit file set rather than lib.cleanSource: the latter keeps target/,
  # so every stray local build ends up copied into the store.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./apply-system.sh
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [ dbus ];

  postInstall = ''
    install -Dm555 apply-system.sh $out/libexec/stewos-apply-system
    substituteInPlace $out/libexec/stewos-apply-system \
      --replace-fail "@nix@" "${nix}"
  '';

  # git and nix are subprocesses of the daemon. run0 (the privilege path) is
  # deliberately not wrapped in: it must talk to the running system's PID 1,
  # so the system's own copy from the base PATH is the right one.
  #
  # The icons are set-default rather than set: this is only the fallback
  # palette, and the home-manager module passes a recoloured set on the command
  # line. Keeping them out of the build inputs proper is the point -- a palette
  # change must not recompile the crate.
  postFixup = ''
    wrapProgram $out/bin/stewos-update-manager \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          nix
        ]
      } \
      --set-default STEWOS_UPDATE_ICON_DIR ${update-manager-icons}/share/icons
  '';

  meta = {
    description = "Manual NixOS + Home-Manager update checker/applier with an SNI tray icon";
    platforms = lib.platforms.linux;
    mainProgram = "stewos-update-manager";
  };
}
