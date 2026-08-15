{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  home.packages =
    (with pkgs; [
      discord
      gimp
      signal-desktop
      spotify
      solaar
      opencode
      nixfmt
      github-cli
    ])
    ++ [
      # From llm-agents.nix rather than nixpkgs, which lags upstream releases.
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    ];

  stewos = {
    desktop = {
      enable = true;
      modifier = "ALT";
      startLocked = true;

      # wallpaper = pkgs.fetchurl {
      #   url = "https://i.redd.it/uhmtqleyl2sd1.jpeg";
      #   sha256 = "sha256-Kh1bYNBodOBN4PDnuO1ko4rB12xAOOdSNYUnDFb0z+0=";
      # };

      # wallpaper = pkgs.fetchurl {
      #   url = "https://lh3.googleusercontent.com/pw/AP1GczM8Zlkuq2_ccOHyjjfHodRhXjmujKWSwpy8_XOEMiOxvBOo2ZYNT4mN_LwiTHBWrvlcuU-db7uTTnhU6zODkIW3f85L2XErIfWNkuBru9Ws5sFyIos5nBPN_JWuFMCX9-j5gDnl6cXsUkBUR2pYdgfEAQ=w3468-h1951-s-no?authuser=0";
      #   hash = "sha256-uy0TQ+K15h6IMmv3Tbd15+nM3XR/rD/1GYZQxQUoRjQ=";
      #   # url = "https://lh3.googleusercontent.com/pw/AP1GczMFuTffAIDMFEND7odg-nmIPaEgPIPhGwv94oxhpFFe5CN4QunlA77wz4raxgTZ68Uje2SPmBhR1A5iluCevPDUSsueXyViocCrZUDVPYKAeazOJGgTYoGgH-6CqRohmh42vi7giZoUiAep4XHn8BjULg=w3591-h2020-s-no";
      #   # hash = "sha256-gAAV3OkG66ZonBjV0brY/Br6vsxIbws+lQRqyUN35Mg=";
      # };

      monitors =
        let
          # Unique names of monitors in the horizontal order they are
          # configured in the real world.
          orderedNames = [
            "Dell Inc. DELL U2723QE 55L01P3"
            "Dell Inc. DELL U2723QE HXJ01P3"
          ];

          # Resolution used for all monitors
          resolution = {
            width = 3840;
            height = 2160;
          };

          # Scale used for all monitors
          scale = 1.5;
        in
        # Configure all monitors in orderedNames and set their X positions
        # appropriately based on their index in the ordered list, the
        # resolution width and the scaling factor.
        lib.imap0 (i: description: {
          inherit resolution description scale;
          position.x = (builtins.floor (resolution.width / scale)) * i;
        }) orderedNames;
    };

    embermug-tray.enable = true;
    update-manager.enable = true;

    git.enable = true;
    alacritty.enable = true;
    bat.enable = true;
    firefox.enable = true;
    eza.enable = true;
    rofi.enable = true;
    zsh.enable = true;
    neovim.enable = true;
    zoxide.enable = true;
    direnv.enable = true;
  };

  colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

  # caelestia's idle chain ends in `suspendThenHibernate`, which is what walked
  # this machine into the dead-GPU lockup: the hibernate leg cannot succeed here
  # (see configuration.nix), and the abort takes amdgpu with it. The defaults
  # live in the plugin's C++, not in QML -- `GeneralIdle` in
  # plugin/src/Caelestia/Config/generalconfig.hpp. Note that a checkout of the
  # shell may carry an older QML-based config tree that spells this differently;
  # the flake input is what builds.
  #
  # `["systemctl", "suspend"]` is not exec'd: SessionManager::exec aliases a
  # two-element systemctl/loginctl invocation to the bare verb and calls logind
  # over D-Bus, so this lands on the same path the default did.
  #
  # Restated in full rather than patched, because `timeouts` is a JSON list --
  # the module system replaces it, it does not merge element-wise. The delays
  # are longer than caelestia's 180/300/600 defaults: this machine lives at
  # home, where an unattended screen is not much of a threat.
  programs.caelestia.settings.general.idle.timeouts = [
    {
      timeout = 600;
      idleAction = "lock";
    }
    {
      timeout = 900;
      idleAction = "dpms off";
      returnAction = "dpms on";
    }
    {
      timeout = 1200;
      idleAction = [
        "systemctl"
        "suspend"
      ];
    }
  ];

  # Setup Chrome
  programs.chromium = {
    enable = true;
    # No Wayland flags needed: the google-chrome wrapper already adds
    # "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations
    # --enable-wayland-ime=true" when NIXOS_OZONE_WL is set, which
    # stewos.desktop-services does system-wide.
    package = pkgs.google-chrome;

    # extensions =
    #   let
    #     lastpass.id = "hdokiejnpimakedhajhdlcegeplioahd";
    #   in
    #   [
    #     lastpass
    #   ];
  };
}
