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

  # Upstream prints only the marketing name ("Apple M5 Pro") for both CPU and
  # GPU, which does not identify the bin. Adds core counts from sysctl and the
  # IORegistry. Not yet filed -- ./upstream/ holds the issue text and the plan
  # for taking it upstream. Touches only src/, so cargoHash is unaffected: the
  # vendor derivation hashes the unpatched source.
  patches = [ ./cpu-gpu-core-counts.patch ];

  cargoHash = "sha256-5g/QQH0N0AwQfO9nGfYgV4iG3yQYeNXiJV1m0SbQY8U=";

  # utils::cache's tests exercise the real /Library/Caches/macfetch instead of a
  # temp dir, so checkPhase leaves a directory owned by the nix build user on
  # the host -- which then makes the cache silently unwritable for the logged-in
  # user. See ./upstream/issue-cache-tests-pollute-real-cache.md.
  checkFlags = [ "--skip=macfetch::utils::cache::tests" ];

  meta = {
    description = "Neofetch alternative for macOS, written in Rust";
    homepage = "https://github.com/gantoreno/macfetch";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "macfetch";
  };
})
