{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  dbus,
  git,
  nix,
}:
rustPlatform.buildRustPackage {
  pname = "stewos-update-manager";
  version = "0.1.0";

  src = lib.cleanSource ./.;
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
  postFixup = ''
    wrapProgram $out/bin/stewos-update-manager \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          nix
        ]
      }
  '';

  meta = {
    description = "Manual NixOS + Home-Manager update checker/applier with an SNI tray icon";
    platforms = lib.platforms.linux;
    mainProgram = "stewos-update-manager";
  };
}
