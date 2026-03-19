{
  lib,
  fetchFromGitHub,
  pnpm,
  nodejs,
}:
pnpm.buildPnpmPackage {
  pname = "shortcut-cli";
  version = "5.0.0";

  src = fetchFromGitHub {
    owner = "shortcut-cli";
    repo = "shortcut-cli";
    rev = "f0b1469abc100d2a12b902b9ad46f9ae9ea9d4b9";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  nodejs = nodejs;

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/node_modules/@shortcut-cli/shortcut-cli
    cp -r build $out/lib/node_modules/@shortcut-cli/shortcut-cli/
    cp package.json $out/lib/node_modules/@shortcut-cli/shortcut-cli/
    mkdir -p $out/bin
    ln -s $out/lib/node_modules/@shortcut-cli/shortcut-cli/build/bin/short.js $out/bin/short
    chmod +x $out/bin/short
    runHook postInstall
  '';

  meta = {
    description = "A community-driven command line tool for shortcut.com";
    homepage = "https://github.com/shortcut-cli/shortcut-cli";
    license = lib.licenses.mit;
    mainProgram = "short";
  };
}
