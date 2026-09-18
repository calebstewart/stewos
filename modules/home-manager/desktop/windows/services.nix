# How the desktop's daemons run: as steward units
# (github:calebstewart/steward) rather than from the Run key. mkHome gives
# every Windows home steward's home module, which writes systemd.user.* as
# steward's units, and mkWindowsHost turns steward on in the system
# configuration, which installs it. So under steward komorebi, whkd, masir and
# YASB are brought back when they die, stopped at sign-out, and restarted by
# an apply that changes them. (Flow Launcher, for a host that turns it back
# on, stays on the Run key: winpkgs has no service mode for it.)
#
# komorebi, whkd and masir are one group, tiling.target: `stewctl stop
# tiling.target` puts them all away -- komorebi giving back the windows it hid
# -- and `stewctl start tiling.target` brings them back. YASB is not in it: it
# is the launcher and the clock as well as the workspaces, and stays up with
# the session (graphical-session.target) when tiling is put away. Its
# komorebi widgets show komorebi as offline until it is back.
#
# Everything is mkDefault: a host whose system does not run steward sets
# `programs.<name>.service.enable = false`, and that program goes back to the
# Run key (and leaves the group).
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
      programs = lib.genAttrs (daemons ++ [ "yasb" ]) (_: {
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
