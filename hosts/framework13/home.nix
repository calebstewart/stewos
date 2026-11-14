{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  stewos = {
    desktop = {
      enable = true;
      modifier = "ALT";
      startLocked = true;

      monitors = [
        {
          # The built-in 13.5" 2880x1920 panel, 256 PPI. Hyprland matches on
          # the EDID description, so this string must be exactly what
          # `hyprctl monitors` prints for eDP-1; until it is, the panel falls
          # through to the "preferred mode, automatic scale" fallback and
          # nothing else breaks. The panel is CSOT's MND508ZB1-1, so expect
          # the vendor to read "CSO".
          description = "China Star Optoelectronics Technology Co. Ltd MND508ZB1-1";

          # 1.6 is Framework's own recommendation in effect (their guides say
          # 200% then a 0.8 font scale) and it divides the panel exactly, to a
          # 1800x1200 logical desktop. 2 is the integer choice but leaves a
          # 1440x960 desktop, which is cramped at 13.5".
          scale = 1.6;
        }
      ];

      # The built-in keyboard is reached through the EC and enumerates as its
      # own input device, which the session-wide keyboard settings do not
      # reach. The name is what every Framework 13 so far has reported; confirm
      # it with `hyprctl devices` if Caps Lock still acts as Caps Lock.
      keyboards."at-translated-set-2-keyboard".capsLockEscape = true;
    };

    git.enable = true;
    delta.enable = true;
    alacritty.enable = true;
    bat.enable = true;
    firefox.enable = false;
    eza.enable = true;
    rofi.enable = true;
    zsh.enable = true;
    neovim.enable = true;
    zoxide.enable = true;
    direnv.enable = true;
  };

  services.nixos-update-manager.enable = true;

  home.packages =
    (with pkgs; [
      discord
      signal-desktop
      btop
      opencode
    ])
    ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      claude-desktop
    ]);

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "x-scheme-handler/discord" = "discord.desktop";
      "x-scheme-handler/sgnl" = "signal.desktop";
      "x-scheme-handler/signalcaptcha" = "signal.desktop";
      "x-scheme-handler/claude" = "claude-desktop.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  # Try the sidebar on hover rather than on drag, as on framework16. The
  # trigger is the right edge above `max(sidebar.minHoverThreshold, bottom of
  # the notification stack)` -- see Config.sidebar.showOnHover in the shell's
  # modules/drawers/Interactions.qml -- so it is the top-right corner, not the
  # whole right edge. Drag still works; this only adds the hover path.
  programs.caelestia.settings.sidebar.showOnHover = true;

  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  # Setup Chrome
  programs.chromium = {
    enable = true;
    package = pkgs.chromium.override {
      enableWideVine = true;

      commandLineArgs = [
        "--ozone-platform-hint=auto"
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"

        # Fullscreen video corrupts into black/white blocks on this machine
        # (Panther Lake, xe) when Chromium speaks wp_color_management: going
        # fullscreen lets Hyprland's `render.cm_auto_hdr` switch eDP-1 to
        # HDR, and Chromium's colour-managed video is then drawn as garbage.
        # Tested 2026-11-11: HDR on the plain desktop is clean (8- and
        # 10-bit), disabling VA-API decode does not help, disabling this
        # feature does. Turning it off keeps Chromium out of auto-HDR while
        # leaving HDR for every other client.
        "--disable-features=WaylandWpColorManagerV1"
      ];
    };

    extensions =
      let
        lastpass.id = "hdokiejnpimakedhajhdlcegeplioahd";
      in
      [
        lastpass
      ];
  };
}
