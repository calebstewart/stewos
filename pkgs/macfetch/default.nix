{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "macfetch";
  version = "2.3.1";

  src = fetchFromGitHub {
    owner = "gantoreno";
    repo = "macfetch";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ty8qwMHKm+73q78kwOGLhzZX9Gwf7UPfpfRXVESIX5E=";
  };

  cargoHash = "sha256-5g/QQH0N0AwQfO9nGfYgV4iG3yQYeNXiJV1m0SbQY8U=";

  meta = {
    description = "Neofetch alternative for macOS, written in Rust";
    homepage = "https://github.com/gantoreno/macfetch";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "macfetch";
  };
})
