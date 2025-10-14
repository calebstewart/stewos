{buildGoModule, fetchFromGitHub, lib}: buildGoModule rec {
  pname = "hunt-cli";
  version = "1.19.12";

  src = fetchFromGitHub {
    owner = "huntresslabs";
    repo = pname;
    rev = "v${version}";
    fetchSubmodules = true;
    hash = lib.fakeHash;
  };

  vendorHash = lib.fakeHash;
}
