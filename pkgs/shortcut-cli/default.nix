{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  makeWrapper,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "shortcut-cli";
  version = "5.0.0";

  src = fetchFromGitHub {
    owner = "shortcut-cli";
    repo = "shortcut-cli";
    rev = "f0b1469abc100d2a12b902b9ad46f9ae9ea9d4b9";
    hash = "sha256-sbWbzrjgobkMqqmLU7YarCgBc7kUSvbGyjaAForQs5Q=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-YVsLAKCwhOCSxritwE9Wad+lAmDfcZdaHQ8XlUszAQo=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/${finalAttrs.pname} $out/bin
    cp -r build node_modules package.json $out/lib/${finalAttrs.pname}/
    makeWrapper ${nodejs}/bin/node $out/bin/short \
      --add-flags "$out/lib/${finalAttrs.pname}/build/bin/short.js"
    runHook postInstall
  '';

  meta = {
    description = "A community-driven command line tool for shortcut.com";
    homepage = "https://github.com/shortcut-cli/shortcut-cli";
    license = lib.licenses.mit;
    mainProgram = "short";
  };
})
