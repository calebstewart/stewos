# How the desktop's daemons run: as steward units
# (github:calebstewart/steward) rather than from the Run key. mkHome gives
# every Windows home steward's home module, which writes systemd.user.* as
# steward's units, and mkWindowsHost turns steward on in the system
# configuration, which installs it. So under steward komorebi, whkd and masir
# are brought back when they die, stopped at sign-out, and restarted by an
# apply that changes them. Flow Launcher stays on the Run key: winpkgs has no
# service mode for it (see its module for why).
#
# komorebi, its bars, whkd and masir are one group, tiling.target: `stewctl
# stop tiling.target` puts them all away -- komorebi giving back the windows it
# hid -- and `stewctl start tiling.target` brings them back. The bars are part
# of komorebi's own unit (winpkgs), so they come and go with it.
#
# Everything is mkDefault: a host whose system does not run steward sets
# `programs.<name>.service.enable = false`, and that program goes back to the
# Run key and leaves the group.
{
  options,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  daemons = [
    "komorebi"
    "whkd"
    "masir"
  ];
  tiling = lib.filter (name: config.programs.${name}.service.enable) daemons;
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      programs = lib.genAttrs daemons (_: {
        service.enable = lib.mkDefault true;
      });

      systemd.user.targets.tiling = lib.mkIf (tiling != [ ]) {
        Unit.Description = "Tiling window management: komorebi and its bars, whkd, masir";
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # In place of winpkgs' own WantedBy (graphical-session.target, at
      # mkDefault), so that starting and stopping the target is what starts
      # and stops them.
      systemd.user.services = lib.genAttrs tiling (_: {
        Unit.PartOf = [ "tiling.target" ];
        Install.WantedBy = [ "tiling.target" ];
      });
    }
  );
}
