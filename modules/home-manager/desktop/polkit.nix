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
      # The header text carries no clampSize, and hyprtoolkit ellipsizes
      # unclamped auto-sized text after a fractional-scale change (the text's
      # room hint is its own scale-1.0 preferred size and never re-grows).
      # Clamping it like the dialog's other texts makes it wrap-mode instead,
      # and it fits on one line anyway. Drop the patch when fixed upstream.
      package =
        (inputs.hyprpolkitagent.packages.${pkgs.stdenv.hostPlatform.system}.default).overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [ ./patches/hyprpolkitagent-clamp-header.patch ];
          });
    };

    systemd.user.services.hyprpolkitagent = {
      # The home-manager unit has no Restart policy; add one.
      Service = {
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };
}
