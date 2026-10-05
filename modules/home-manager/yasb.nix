# YASB (github:amnweb/yasb), a Qt status bar for Windows with widgets for
# komorebi and GlazeWM. `settings` is config.yaml and `style` is styles.css,
# both in ~/.config/yasb, which is where YASB looks without YASB_CONFIG_HOME.
# The Run key runs before a user variable set in a shell profile would exist,
# so the module does not move them.
#
# Written the way winpkgs' own program modules are (programs.masir,
# programs.whkd), so that it can move there unchanged. Two parts are
# StewOS-specific, because this tree is imported by every home and not only
# winpkgs ones: the fallback in `package`'s default, and the guard around
# `config`. windows.* is declared only in a winpkgs home, and a definition of
# an undeclared option is an error even under a false mkIf, so without the
# guard the Linux and macOS homes would not evaluate (see
# desktop/windows/default.nix). It tests `options` rather than `pkgs` for the
# same recursion reason. Upstreamed, both go.
#
# Starting it: yasb.exe is a GUI program, so the Run entry is the executable
# itself. The value is named `YASB` because that is the value `yasbc
# enable-autostart` and the tray menu's "Enable Autostart" write, so this one
# takes its place rather than starting a second bar. `service.enable` runs it
# as home-manager's `systemd.user.services.yasb` instead, for a user service
# manager (steward, whose home module writes them as units). Stopped with
# `yasbc stop`, so the bar gives back the work area it reserved as an app bar.
#
# Reloading: YASB watches both files (`watch_config` and `watch_stylesheet`,
# on by default), but its watcher only acts on a file being *modified*, and
# winpkgs applies a file by removing it and copying the new one in. So a
# change is not guaranteed to be picked up in place. As a service, a changed
# file restarts the unit; from the Run key, `yasbc reload` does it by hand.
{
  options,
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.programs.yasb;
  yaml = pkgs.buildPackages.formats.yaml { };

  configFile = yaml.generate "yasb-config.yaml" cfg.settings;
  styleFile =
    if builtins.isPath cfg.style || lib.isStorePath cfg.style then
      cfg.style
    else
      pkgs.buildPackages.writeText "yasb-styles.css" cfg.style;

  yasbc = lib.removeSuffix "yasb.exe" cfg.executable + "yasbc.exe";
  commandLine = ''"${cfg.executable}"'';

  configDir = "%USERPROFILE%/.config/yasb";
in
{
  options.programs.yasb = {
    enable = mkEnableOption "YASB, a status bar";

    package = mkOption {
      type = types.nullOr types.package;
      # StewOS-specific, like the guard below: pkgs.winpkgs exists only in a
      # winpkgs home, and the docs generator forces every default on its
      # Linux stub host, where a missing attribute is not an error tryEval
      # can catch. Upstreamed, this is the fromWinget call alone.
      default =
        if pkgs ? winpkgs then
          pkgs.winpkgs.fromWinget {
            id = "AmN.yasb";
            scope = "machine";
            programDir = ''%ProgramFiles%\YASB'';
            mainProgram = "yasb";
          }
        else
          null;
      defaultText = lib.literalExpression ''
        pkgs.winpkgs.fromWinget {
          id = "AmN.yasb";
          scope = "machine";
          programDir = '''%ProgramFiles%\YASB''';
          mainProgram = "yasb";
        }
      '';
      description = ''
        The package to install. winget's is an MSI, so it is machine scope and
        reaches the system configuration through `winpkgs.homes`. `null`
        installs nothing.
      '';
    };

    executable = mkOption {
      type = types.str;
      default = ''C:\Program Files\YASB\yasb.exe'';
      description = ''
        The path of yasb.exe, for the start-up entry: the MSI's location by
        default. `yasbc.exe`, which stops the service, is taken to be beside
        it.
      '';
    };

    settings = mkOption {
      inherit (yaml) type;
      default = { };
      example = lib.literalExpression ''
        {
          update_check = false;
          bars.primary-bar = {
            screens = [ "*" ];
            alignment = { position = "top"; align = "center"; };
            dimensions = { width = "100%"; height = 32; };
            widgets = {
              left = [ "workspaces" ];
              right = [ "clock" ];
            };
          };
          widgets = {
            workspaces.type = "komorebi.workspaces.WorkspaceWidget";
            clock = {
              type = "yasb.clock.ClockWidget";
              options.label = "{%H:%M}";
            };
          };
        }
      '';
      description = ''
        YASB's config.yaml, written to `~/.config/yasb/config.yaml` when not
        empty. Taken as given: YASB validates the file itself and rejects keys
        it does not know, so see its wiki for the schema. `update_check =
        false` suits a winget-managed install, which winpkgs keeps up to date.
      '';
    };

    style = mkOption {
      type = types.nullOr (types.either types.path types.lines);
      default = null;
      example = lib.literalExpression ''
        '''
          :root { --bg: #1e1e2e; }
          .yasb-bar { background-color: var(--bg); }
        '''
      '';
      description = ''
        YASB's styles.css, as a file or as its text, written to
        `~/.config/yasb/styles.css`. Qt style sheets, which YASB preprocesses:
        `:root` variables with `var()`, and `@import` relative to the file.
        `null` writes nothing.
      '';
    };

    autostart = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start YASB at sign-in, through `windows.startup.YASB` -- the entry
        YASB's own autostart writes, which this replaces. Moot with
        `service.enable`.
      '';
    };

    service.enable = mkEnableOption ''
      YASB as a user service instead of a Run entry: `systemd.user.services.yasb`,
      which a user service manager runs (steward's home module makes it a
      unit). Started with `graphical-session.target` unless the unit says
      otherwise -- after komorebi's service, when there is one -- restarted if
      it dies or its files change, and stopped with `yasbc stop`. The Run
      entry is removed, including one YASB wrote itself'';
  };

  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf cfg.enable {
      home.packages = lib.optional (cfg.package != null) cfg.package;

      windows.files."${configDir}/config.yaml" = lib.mkIf (cfg.settings != { }) {
        source = configFile;
      };
      windows.files."${configDir}/styles.css" = lib.mkIf (cfg.style != null) {
        source = styleFile;
      };

      windows.startup.YASB = if cfg.service.enable then null else lib.mkIf cfg.autostart commandLine;

      systemd.user.services.yasb = lib.mkIf cfg.service.enable {
        Unit = {
          Description = "YASB, a status bar";
          # Ordering only: YASB runs without komorebi, and its komorebi
          # widgets reconnect when it comes up.
          After = [
            "graphical-session.target"
            "komorebi.service"
          ];
          # A changed file is not reliably reloaded in place (see above).
          X-Restart-Triggers =
            lib.optional (cfg.settings != { }) configFile ++ lib.optional (cfg.style != null) styleFile;
        };
        Service = {
          ExecStart = commandLine;
          ExecStop = ''"${yasbc}" stop'';
        };
        Install.WantedBy = lib.mkDefault [ "graphical-session.target" ];
      };
    }
  );
}
