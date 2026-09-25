{
  lib,
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
