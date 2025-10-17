{
  inputs,
  lib,
  buildNpmPackage,
  bun,
}:
buildNpmPackage {
  pname = "gh-actions-language-server";
  version = "0.3.13";
  src = inputs.gh-actions-language-server;

  postPatch = ''
    ln -s ${./package-lock.json} package-lock.json
  '';

  buildPhase = ''
    ${lib.getExe bun} ./build/node.ts
  '';

  npmDepsHash = "sha256-/VPw2dT//xMjTvSxaK26i9fjYR1EGhogfiWq6xsvwfE=";
  npmBuildScript = "build:node";

  meta = {
    description = "GitHub Actions Language Server";
    homepage = "https://github.com/ittb/gh-actions-language-server";
    license = lib.licenses.mit;
  };
}
