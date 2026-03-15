{
  inputs,
  system,
  lib,
}:
let
  nordvpn = inputs.nur.legacyPackages.${system}.repos.wingej0.nordvpn;
in
nordvpn.overrideAttrs (old: {
  # This is nested inside itself which breaks icon resolution
  postInstall = (old.postInstall or "") + ''
    mv $out/share/share $out/share2
    rmdir $out/share
    mv $out/share2 $out/share
  '';

  # I fucking hate this shit.
  meta.license = lib.licenses.free;
})
