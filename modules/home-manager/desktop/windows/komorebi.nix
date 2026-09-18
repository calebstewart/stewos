# komorebi, the tiling window manager. The bar along the top of each monitor
# is YASB's (./yasb.nix), not komorebi-bar, which stays at winpkgs' default of
# off: komorebi reserves room for every bar it is configured with, running or
# not, so leaving it configured beside YASB would stack the two gaps.
#
# What a host still says for itself is its monitors: komorebi takes the
# workspaces of each one from `programs.komorebi.settings.monitors`, indexed
# by komorebi's own monitor numbers. The workspace bindings in ./bindings.nix
# reach the first five of the focused monitor, so five per monitor is the
# shape to give it.
{
  options,
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      programs.komorebi = {
        enable = true;

        # The community application rules (a pinned flake input): what makes
        # the Snipping Tool overlay, installers and tray apps float or be
        # ignored.
        applications = lib.mkDefault "${inputs.komorebi-asc}/applications.json";

        settings = lib.mkMerge [
          (lib.mapAttrs (_: lib.mkDefault) {
            # Focus follows the mouse instead (masir, ./default.nix).
            mouse_follows_focus = false;
            window_hiding_behaviour = "Cloak";
            cross_monitor_move_behaviour = "Insert";

            # The same gaps as Aerospace's.
            default_workspace_padding = 5;
            default_container_padding = 5;

            border = true;
            border_width = 1;
            border_offset = -1;
          })

          {
            # Flow Launcher, for a host that turns it back on (./default.nix);
            # the community rules have no entry for it. Its confirmations (log off, restart, ...) are WPF
            # windows titled with their own prompt text and sharing an
            # HwndWrapper class with everything else it opens, so nothing
            # narrower than the exe picks them out. The launcher itself is
            # never managed; the settings window floats too. Not mkDefault, so
            # a host's own floating_applications add to this rather than
            # replace it.
            floating_applications = lib.mkIf config.programs.flow-launcher.enable [
              {
                kind = "Exe";
                id = "Flow.Launcher.exe";
                matching_strategy = "Equals";
              }
            ];
          }
        ];
      };
    }
  );
}
