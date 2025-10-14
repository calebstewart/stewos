{lib, config, pkgs, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    home.packages = [pkgs.raycast];
  };
}
