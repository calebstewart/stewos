{
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
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    # The Hyprland polkit authentication agent, which draws the
    # privilege-escalation prompts (run0, pkexec, ...). The package comes from
    # the upstream flake because nixpkgs still ships the pre-hyprtoolkit Qt
    # build (see the input comment in flake.nix).
    services.hyprpolkitagent = {
      enable = true;
      package = inputs.hyprpolkitagent.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    systemd.user.services.hyprpolkitagent = {
      # The home-manager unit has no Restart policy; add one.
      Service = {
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };

      # The agent only reads its config at startup. Embedding the config's
      # store path in the unit makes the unit change whenever the config
      # does, so sd-switch restarts the agent on activation.
      Unit.X-Restart-Triggers = [
        "${config.xdg.configFile."hyprpolkitagent/hyprpolkitagent.conf".source}"
      ];
    };

    # The agent draws a fixed-size window and auto-sizes the content inside
    # it, so an oversized window reads as heavy padding. Size it relative to
    # the monitor. The agent honours the height but renders at its minimum
    # width regardless of window_width (upstream bug), so the width is
    # enforced by the window rule in hyprland.nix; it is still written here
    # so the agent's internal layout targets agree once upstream fixes it.
    # password_field_width also caps the width of every text line in the
    # dialog (message, command, identity), so derive it from the dialog width
    # or the content stays pinned at the 340px default and ellipsizes early.
    xdg.configFile."hyprpolkitagent/hyprpolkitagent.conf".text = ''
      general {
        window_width = ${toString cfg.authDialogSize.width}
        window_height = ${toString cfg.authDialogSize.height}
        password_field_width = ${toString (cfg.authDialogSize.width - 120)}
      }
    '';
  };
}
