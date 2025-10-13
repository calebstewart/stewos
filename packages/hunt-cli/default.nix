{buildGoModule, fetchgit, lib}: buildGoModule rec {
  pname = "hunt-cli";
  version = "1.19.12";

  src = fetchgit {
    url = "git@github.com:huntresslabs/${pname}#refs/tags/v${version}";
    hash = lib.fakeHash;
  };

  vendorHash = lib.fakeHash;
}
