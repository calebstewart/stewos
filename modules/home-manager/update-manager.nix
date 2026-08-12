{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.update-manager;
  palette = config.colorScheme.palette;

  mkIconColor =
    when: slot:
    lib.mkOption {
      type = lib.types.str;
      default = "#${palette.${slot}}";
      description = "Colour of the icon shown ${when}.";
    };
in
{
  options.stewos.update-manager = {
    enable = lib.mkEnableOption "the StewOS update-manager tray daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.stewos.update-manager;
      description = "The update-manager package to run.";
    };

    # These exist rather than leaving everything to
    # pkgs.stewos.update-manager-icons.override because pkgs/ may not read
    # config and the module may: defaulting each colour out of the palette is
    # what makes the tray follow a colour-scheme change, the way theme.nix does
    # for the rest of the desktop. Overriding one of them keeps the other five
    # scheme-derived.
    icons = {
      # base05 (the plain foreground) rather than one of the greys: this is the
      # state with nothing to say, and base03/base04 are surface colours that
      # all but disappear against a bar.
      idle = mkIconColor "when no check has run yet" "base05";
      checking = mkIconColor "while checking for updates" "base0D";
      upToDate = mkIconColor "when up to date" "base0B";
      updatesAvailable = mkIconColor "when updates are waiting to be applied" "base0A";
      applying = mkIconColor "while applying updates" "base0E";
      error = mkIconColor "when the last operation failed" "base08";

      # The menu glyphs are actions, so they take no meaning from their hue and
      # share one neutral colour.
      menu = mkIconColor "on the tray menu's own entries" "base05";
    };

    iconPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.stewos.update-manager-icons.override cfg.icons;
      defaultText = lib.literalExpression "pkgs.stewos.update-manager-icons.override config.stewos.update-manager.icons";
      description = ''
        Rendered icon theme the daemon draws its tray and notification icons
        from. The daemon is pointed at it with `--icon-dir`, so this -- not
        {option}`package` -- is the icon knob while the module is in charge;
        overriding `update-manager-icons` on {option}`package` only affects the
        binary's own default, which the unit overrides.
      '';
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/git/stewos";
      description = "Git checkout of the flake to update and merge back into.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "stewos-update";
      description = "Branch the update check builds on.";
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [ cfg.package ];

    systemd.user.services.stewos-update-manager = {
      Unit = {
        Description = "StewOS update-manager tray daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe cfg.package)
          "--flake ${cfg.flakePath}"
          "--branch ${cfg.branch}"
          "--icon-dir ${cfg.iconPackage}/share/icons"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
