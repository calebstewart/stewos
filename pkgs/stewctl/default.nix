{
  lib,
  stdenv,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "stewctl";
  version = "0.1.0";

  # An explicit file set rather than lib.cleanSource, which would keep target/.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  # Rust records source paths for panic messages, and the vendored crates live
  # in the store. winpkgs refuses to install a file that mentions /nix/store/,
  # so on Windows the paths are rewritten and postInstall proves it -- the
  # recipe steward's own package uses.
  preBuild = lib.optionalString stdenv.hostPlatform.isWindows ''
    export RUSTFLAGS="''${RUSTFLAGS-} --remap-path-prefix=/nix/store=/store --remap-path-prefix=$NIX_BUILD_TOP=/build"
  '';
  postInstall = lib.optionalString stdenv.hostPlatform.isWindows ''
    if grep -l --binary-files=text /nix/store/ $out/bin/*; then
      echo "the binaries above mention /nix/store/; winpkgs would refuse them" >&2
      exit 1
    fi
  '';

  # A cross build cannot run Windows test binaries; the tests run natively.
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  meta = {
    description = "Build and switch any StewOS host's system or home configuration";
    longDescription = ''
      One command for every StewOS machine: `stewctl os <verb>` for the system
      configuration and `stewctl home <verb>` for the user's, the same on
      NixOS, macOS and Windows. It is a dispatcher -- nh does the work on NixOS
      and macOS, winpkgs on Windows -- that finds the configuration from the
      os.json and home.json the StewOS modules write, rather than from the
      hostname.
    '';
    homepage = "https://github.com/calebstewart/stewos";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "stewctl";
  };
}
