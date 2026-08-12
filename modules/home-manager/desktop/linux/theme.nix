# Application theming, for every toolkit that shows up on this desktop.
#
# There are four of them, and they each want telling in a different way:
#  - GTK 3 and 4, through gtk.* and a generated stylesheet.
#  - hyprtoolkit-native apps, through hypr/hyprtoolkit.conf.
#  - the org.hyprland.style QML style used by the Qt/QML hypr apps (today:
#    hyprpolkitagent's auth dialog).
#  - every other Qt6 app, through hyprqt6engine, whose platform theme plugin is
#    installed here and configured by hypr/hyprqt6engine.conf.
#
# All four are driven from config.colorScheme, the same palette ./style.nix
# draws the compositor's own chrome from, so changing the scheme changes the
# whole desktop rather than half of it.
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  palette = config.colorScheme.palette;

  # Theming a palette cannot express. Cursors and tinted folder icons are image
  # sets that ship per flavour, so they have to be picked rather than derived.
  # An unmapped scheme falls back to a neutral pair, which keeps a colour scheme
  # swap working -- if less prettily -- instead of failing to evaluate.
  schemeAssets = {
    catppuccin-mocha = {
      cursor = {
        name = "catppuccin-mocha-dark-cursors";
        package = pkgs.catppuccin-cursors.mochaDark;
      };
      icons = {
        name = "Papirus";
        package = pkgs.catppuccin-papirus-folders.override {
          flavor = "mocha";
          accent = "blue";
        };
      };
    };
  };

  assets =
    schemeAssets.${config.colorScheme.slug} or {
      cursor = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      icons = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

  hyprqt6engine = inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The engine installs its Qt plugins at lib/qt-6/{platformthemes,styles},
  # but home-manager's QT_PLUGIN_PATH points at the profile's
  # lib/qt-6/plugins directory. Re-root them so the profile picks them up.
  hyprqt6enginePlugins = pkgs.runCommand "hyprqt6engine-plugins" { } ''
    mkdir -p $out/${pkgs.qt6.qtbase.qtPluginPrefix}
    ln -s ${hyprqt6engine}/lib/qt-6/platformthemes \
      $out/${pkgs.qt6.qtbase.qtPluginPrefix}/platformthemes
    ln -s ${hyprqt6engine}/lib/qt-6/styles \
      $out/${pkgs.qt6.qtbase.qtPluginPrefix}/styles
  '';

  # libadwaita refuses third-party themes but does honour these named colours,
  # and adw-gtk3 backports the same names to GTK 3 -- so one stylesheet themes
  # both toolkits, which is more than the GTK 3 theme package alone ever did.
  gtkPaletteCss = ''
    @define-color accent_color #${palette.base0D};
    @define-color accent_bg_color #${palette.base0D};
    @define-color accent_fg_color #${palette.base00};

    @define-color window_bg_color #${palette.base00};
    @define-color window_fg_color #${palette.base05};
    @define-color view_bg_color #${palette.base00};
    @define-color view_fg_color #${palette.base05};

    @define-color headerbar_bg_color #${palette.base01};
    @define-color headerbar_fg_color #${palette.base05};
    @define-color sidebar_bg_color #${palette.base01};
    @define-color sidebar_fg_color #${palette.base05};
    @define-color sidebar_border_color #${palette.base01};
    @define-color sidebar_backdrop_color #${palette.base01};
    @define-color popover_bg_color #${palette.base01};
    @define-color popover_fg_color #${palette.base05};
    @define-color card_bg_color #${palette.base01};
    @define-color card_fg_color #${palette.base05};
    @define-color dialog_bg_color #${palette.base01};
    @define-color dialog_fg_color #${palette.base05};

    @define-color destructive_bg_color #${palette.base08};
    @define-color error_bg_color #${palette.base08};
    @define-color warning_bg_color #${palette.base0A};
    @define-color success_bg_color #${palette.base0B};
  '';

  # A qt5ct-format palette: three rows of 22 comma separated #AARRGGBB values,
  # in QPalette::ColorRole order. hyprqt6engine reads the file with QSettings
  # and hands the rows straight to QPalette, so generating it here is enough --
  # no theme package needs to ship one.
  qtColorRow =
    {
      text,
      highlight,
      highlightedText,
      button,
      link,
      linkVisited,
    }:
    lib.concatStringsSep ", " (
      map (colour: "#ff${colour}") [
        text # WindowText
        button # Button
        palette.base04 # Light
        palette.base02 # Midlight
        palette.base01 # Dark
        palette.base01 # Mid
        text # Text
        palette.base05 # BrightText
        text # ButtonText
        palette.base00 # Base
        palette.base01 # Window
        palette.base01 # Shadow
        highlight # Highlight
        highlightedText # HighlightedText
        link # Link
        linkVisited # LinkVisited
        palette.base01 # AlternateBase
        "ffffff" # NoRole
        palette.base00 # ToolTipBase
        palette.base05 # ToolTipText
      ]
      ++ [
        "#80${palette.base04}" # PlaceholderText, deliberately translucent
        "#ff${highlight}" # Accent
      ]
    );

  qtColorScheme = pkgs.writeText "${config.colorScheme.slug}-qt.conf" ''
    [ColorScheme]
    active_colors=${
      qtColorRow {
        text = palette.base05;
        highlight = palette.base0D;
        highlightedText = palette.base00;
        button = palette.base03;
        link = palette.base0D;
        linkVisited = palette.base07;
      }
    }
    inactive_colors=${
      qtColorRow {
        text = palette.base04;
        highlight = palette.base02;
        highlightedText = palette.base04;
        button = palette.base00;
        link = palette.base04;
        linkVisited = palette.base04;
      }
    }
    disabled_colors=${
      qtColorRow {
        text = palette.base03;
        highlight = palette.base01;
        highlightedText = palette.base03;
        button = palette.base02;
        link = palette.base03;
        linkVisited = palette.base03;
      }
    }
  '';
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    gtk = {
      enable = true;

      # adw-gtk3 exists to follow libadwaita's named colours, which is what
      # makes the generated stylesheet below apply to GTK 3 as well as GTK 4.
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };

      # libadwaita ignores theme packages, so there is nothing to name here.
      gtk4.theme = null;

      gtk3.extraCss = gtkPaletteCss;
      gtk4.extraCss = gtkPaletteCss;

      cursorTheme = {
        inherit (assets.cursor) name package;
      };

      iconTheme = {
        inherit (assets.icons) name package;
      };

      font = {
        inherit (cfg.fonts.ui) name size package;
      };
    };

    # Double-check that the cursor is set properly (it's finicky)
    home.pointerCursor = {
      enable = true;
      gtk.enable = true;
      inherit (assets.cursor) name package;
    };

    # Dark mode is best mode
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };

    qt = {
      enable = true;
      # The Hyprland Qt6 platform theme. Colours, fonts, icons and the widget
      # style for Qt apps come from ~/.config/hypr/hyprqt6engine.conf below.
      # Note this is Qt6-only; Qt5 apps fall back to Qt defaults.
      platformTheme.name = "hyprqt6engine";
    };

    home.packages = [ hyprqt6enginePlugins ];

    programs.hyprland-qt-support = {
      enable = true;
      settings = {
        roundness = 1;
        border_width = 1;
        reduce_motion = false;
      };
    };

    # caelestia's "scheme" support also writes these two files, from a Material
    # You palette it derives from the wallpaper, and it is not shy about it --
    # see apply_gtk in the CLI's utils/theme.py. We want the GTK toolkits on
    # config.colorScheme with the rest of the desktop, so take the files off it.
    #
    # Without "force" activation aborts rather than clobbering the copy
    # caelestia already left behind. With it, home-manager wins and caelestia's
    # write fails against a read-only store symlink -- which its @log_exception
    # wrapper swallows, so the rest of its theming still applies.
    xdg.configFile."gtk-3.0/gtk.css".force = true;
    xdg.configFile."gtk-4.0/gtk.css".force = true;

    # All options are top-level (no category blocks); colours are 0xAARRGGBB.
    # Sizes and rounding keep the toolkit defaults.
    xdg.configFile."hypr/hyprtoolkit.conf".text = ''
      background = 0xFF${palette.base01}
      base = 0xFF${palette.base00}
      alternate_base = 0xFF${palette.base02}
      text = 0xFF${palette.base05}
      bright_text = 0xFF${palette.base06}
      accent = 0xFF${palette.base0D}
      accent_secondary = 0xFF${palette.base0C}

      font_family = ${cfg.fonts.ui.name}
      font_family_monospace = ${cfg.fonts.monospace.name}
      icon_theme = ${assets.icons.name}
    '';

    # "hyprqt6engine" here is the engine's own proxy widget style, not the
    # platform theme named above.
    xdg.configFile."hypr/hyprqt6engine.conf".text = ''
      theme {
        color_scheme = ${qtColorScheme}
        icon_theme = ${assets.icons.name}
        style = hyprqt6engine
        font = ${cfg.fonts.ui.name}
        font_size = ${toString cfg.fonts.ui.size}
        font_fixed = ${cfg.fonts.monospace.name}
        font_fixed_size = ${toString cfg.fonts.monospace.size}
      }
    '';
  };
}
