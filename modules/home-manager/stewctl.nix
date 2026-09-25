# ~/.config/stewctl/home.json: which home configuration this is. stewctl itself
# comes from the system configuration.
#
# Not on Windows yet: stewctl is not installed there, and nothing reads it.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.stewctl;
in
{
  imports = [ ../common/stewctl.nix ];

  config = lib.mkIf (cfg.enable && !pkgs.stdenv.hostPlatform.isWindows) {
    xdg.configFile."stewctl/home.json".text = builtins.toJSON (
      lib.filterAttrs (_: v: v != null) { inherit (cfg) flake attribute; }
    );
  };
}
