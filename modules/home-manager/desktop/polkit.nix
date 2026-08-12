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

    # The home-manager unit has no Restart policy; add one.
    systemd.user.services.hyprpolkitagent.Service = {
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };

    # The agent draws a fixed-size window (default 520x440) and auto-sizes the
    # content inside it, so the default height leaves a large empty area below
    # the buttons. Shrink it to roughly fit the content.
    xdg.configFile."hyprpolkitagent/hyprpolkitagent.conf".text = ''
      general {
        window_width = 520
        window_height = 320
      }
    '';
  };
}
