{
  inputs,
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
      defaultText = lib.literalMD "the `${slot}` slot of {option}`colorScheme.palette`";
      description = "Colour of the icon shown ${when}.";
    };
in
{
  options.stewos.update-manager = {
    enable = lib.mkEnableOption "the StewOS update-manager tray daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.stewos.update-manager;
      defaultText = lib.literalExpression "pkgs.stewos.update-manager";
      description = "The update-manager package to run.";
    };

    # These exist rather than leaving everything to
    # pkgs.stewos.update-manager-icons.override because pkgs/ may not read
    # config and the module may: defaulting each colour out of the palette is
    # what makes the tray follow a colour-scheme change, the way theme.nix does
    # for the rest of the desktop. Overriding one of them keeps the rest
    # scheme-derived.
    #
    # The hues are chosen so the temperature says whose turn it is: cool while
    # the daemon is working (0D checking, 0C building, 0E applying), warm when
    # it is the user's (0A decide, 09 fix the checkout, 08 something broke).
    icons = {
      # base05 (the plain foreground) rather than one of the greys: this is the
      # state with nothing to say, and base03/base04 are surface colours that
      # all but disappear against a bar.
      idle = mkIconColor "when no check has run yet" "base05";
      checking = mkIconColor "while checking for updates" "base0D";
      upToDate = mkIconColor "when up to date" "base0B";
      updatesAvailable = mkIconColor "when an update is waiting to be built or applied" "base0A";
      applying = mkIconColor "while applying updates" "base0E";
      building = mkIconColor "while building the update" "base0C";
      error = mkIconColor "when the last operation failed" "base08";
      blocked = mkIconColor "when uncommitted changes in the checkout block an update" "base09";

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
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/git/stewos"'';
      description = "Git checkout of the flake to update and merge back into.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "stewos-update";
      description = "Branch the update check builds on.";
    };

    # When something fails, the daemon writes a report to its cache directory
    # and opens it in a terminal of its own -- in the editor, or as the opening
    # prompt of a Claude Code session rooted in the flake checkout. These are
    # what it opens it with.
    terminal = lib.mkOption {
      type = lib.types.package;
      default = config.stewos.desktop.terminal;
      defaultText = lib.literalExpression "config.stewos.desktop.terminal";
      description = ''
        Terminal emulator the troubleshooting entries open in. Follows the
        desktop's terminal by default, which is the option a host already sets.
      '';
    };

    terminalArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "-e" ];
      description = ''
        Arguments that make {option}`terminal` run a command, placed before the
        command itself. Empty for a terminal that takes it positionally.
      '';
    };

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = ''
        Editor the failure report opens in. Resolved from the daemon's PATH
        rather than the store on purpose, so it picks up the editor the home
        profile installs (the nixvim-wrapped `nvim`) instead of a second one.
      '';
    };

    claudePackage = lib.mkOption {
      type = lib.types.package;
      default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-code";
      description = ''
        Claude Code used by the "Troubleshoot with Claude" entry. Passed by
        absolute path, so unlike {option}`editor` it does not depend on the
        unit's PATH.
      '';
    };

    checkInterval = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "([0-9]+(s|m|h|d))+");
      default = null;
      example = "6h";
      description = ''
        How often the daemon checks for updates on its own, as a time span
        ("30m", "6h", "1h30m", "1d"). Null means only when asked from the
        tray. A check only evaluates -- it downloads and builds nothing
        unless {option}`autoBuild` is set -- and the daemon never starts one
        while a build or apply is running or the checkout has local changes.
      '';
    };

    autoBuild = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build an update as soon as a scheduled check finds one, instead of
        waiting for "Build update" in the tray or the review dialog. Applying
        is never automatic.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    home.packages = [ cfg.package ];

    systemd.user.services.stewos-update-manager = {
      Unit = {
        Description = "StewOS update-manager tray daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        # escapeShellArgs rather than a plain join: terminalArgs is a
        # user-supplied list, and systemd honours the single quotes it emits.
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--flake"
            cfg.flakePath
            "--branch"
            cfg.branch
            "--icon-dir"
            "${cfg.iconPackage}/share/icons"
            "--terminal"
            (lib.getExe cfg.terminal)
            "--editor"
            cfg.editor
            "--claude"
            (lib.getExe cfg.claudePackage)
          ]
          # Always pass at least one, or the daemon's own "-e" default applies.
          # An empty argument is how "this terminal needs none" is spelled; the
          # daemon drops it.
          ++ lib.concatMap (arg: [
            "--terminal-arg"
            arg
          ]) (if cfg.terminalArgs == [ ] then [ "" ] else cfg.terminalArgs)
          ++ lib.optionals (cfg.checkInterval != null) [
            "--check-interval"
            cfg.checkInterval
          ]
          ++ lib.optional cfg.autoBuild "--auto-build"
        );
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
