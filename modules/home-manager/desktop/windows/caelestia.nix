# The caelestia shell on Windows (stewos.desktop.shell = "caelestia"): the
# same QML the Linux hosts run, under a Windows build of Quickshell
# (github:calebstewart/quickshell, branch `windows`) whose modules stand in
# for the ones caelestia imports -- komorebi behind Quickshell.Hyprland, Core
# Audio behind Quickshell.Services.Pipewire, and so on. It takes YASB's place:
# the bar, the launcher and the notifications.
#
# Four things are installed, and none of them is built here:
#
# - Quickshell itself, with Qt and caelestia's C++ plugin, is a prebuilt
#   bundle (pkgs/quickshell-windows), installed the way winpkgs installs any
#   program that ships as a directory of files: copied to
#   %LOCALAPPDATA%\Programs\quickshell, which goes on the user's PATH.
# - The configuration is upstream's QML with two Linux-only services replaced
#   (pkgs/caelestia-shell/windows.nix), at quickshell/caelestia in the XDG
#   config home, which is where `quickshell --config caelestia` looks. winpkgs
#   points that at AppData\Roaming and sets XDG_CONFIG_HOME to match, and
#   Quickshell honours the variable, so xdg.configFile is right as it stands.
# - shell.json, caelestia's settings, from programs.caelestia.settings -- the
#   option the Linux hosts set, declared by upstream's home-manager module
#   (imported in ../linux/default.nix). Only `settings` is read. The module
#   itself stays off: enabled, it writes a systemd unit that runs a store
#   path. Caelestia keeps its settings beside its state on Windows, in
#   %LOCALAPPDATA%\caelestia, and its own settings page writes the same file,
#   so a change made there lasts until the next apply.
# - scheme.json, its colours, generated from config.colorScheme
#   (lib/caelestia.nix) so the shell matches the terminals, the editor and the
#   window borders.
#
# The plugin in the bundle and the QML have to be one caelestia revision; the
# assertion below is what notices a flake update that moved one of them.
#
# pkgs is a Windows package set without the StewOS overlay (as in
# ../../stewctl.nix), hence callPackage by path, and buildPackages because both
# packages are files fetched and arranged by the machine that evaluates.
{
  inputs,
  options,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;

  bundle = pkgs.buildPackages.callPackage ../../../../pkgs/quickshell-windows { };
  shell = pkgs.buildPackages.callPackage ../../../../pkgs/caelestia-shell/windows.nix {
    caelestia-shell-src = inputs.caelestia-shell;
  };

  inherit (config.programs.caelestia) settings;
  settingsFile = pkgs.buildPackages.writeText "caelestia-shell.json" (builtins.toJSON settings);

  # The shell's colours, from the palette the rest of the desktop renders. On
  # Linux caelestia's CLI writes this file; there is no CLI here, and without
  # the file the shell falls back to the pink scheme built into it.
  schemeFile = pkgs.buildPackages.writeText "caelestia-scheme.json" (
    builtins.toJSON (
      inputs.self.lib.caelestia.mkScheme {
        name = config.colorScheme.slug;
        inherit (config.colorScheme) palette variant;
      }
    )
  );
in
{
  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows && cfg.shell == "caelestia") {
      assertions = [
        {
          assertion = bundle.caelestiaRev == shell.rev;
          message = ''
            The Quickshell bundle carries caelestia's plugin at revision
            ${bundle.caelestiaRev}, and the caelestia-shell input is at
            ${toString shell.rev}. The plugin and the QML are one program and
            have to match: build a bundle for the new revision (ci/windows/
            versions.env in the Quickshell fork) and update
            pkgs/quickshell-windows, or pin the input back.
          '';
        }
      ];

      home.packages = [
        (pkgs.winpkgs.portable "quickshell" bundle)

        # Every icon caelestia draws is a glyph from the first; the second is
        # its default monospace font.
        (pkgs.winpkgs.font pkgs.material-symbols)
        pkgs.nerd-fonts.caskaydia-cove
      ];

      xdg.configFile."quickshell/caelestia".source = shell;

      windows.files."%LOCALAPPDATA%/caelestia/shell.json" = lib.mkIf (settings != { }) {
        source = settingsFile;
      };

      # Caelestia keeps its scheme with its state, which on Windows is the
      # same directory as its settings.
      windows.files."%LOCALAPPDATA%/caelestia/scheme.json".source = schemeFile;

      # Run by steward, like the rest of the desktop's daemons (./services.nix).
      #
      # Through cmd, for the one thing it does here: expand %LOCALAPPDATA%.
      # The bundle is under the user's profile, whose path is not known at
      # evaluation, and steward passes the line to CreateProcess as written.
      # Naming the program and leaving it to PATH does not work either:
      # steward gives a unit a fresh environment but looks the program up on
      # its own PATH, the one from sign-in, so the first apply cannot start
      # it ("The system cannot find the file specified"). /s makes cmd strip
      # exactly the outer quotes, whatever is inside them.
      systemd.user.services.caelestia = {
        Unit = {
          Description = "The caelestia shell";
          # Ordering only: the workspaces show as empty until komorebi is up.
          After = [
            "graphical-session.target"
            "komorebi.service"
          ];
          # Quickshell reloads a changed file in place, but winpkgs replaces
          # files rather than modifying them, and a new bundle needs a new
          # process either way.
          X-Restart-Triggers = [
            bundle
            shell
            schemeFile
          ]
          ++ lib.optional (settings != { }) settingsFile;
        };
        Service.ExecStart = ''C:\Windows\System32\cmd.exe /d /s /c ""%LOCALAPPDATA%\Programs\quickshell\quickshell.exe" --config caelestia"'';
        Install.WantedBy = lib.mkDefault [ "graphical-session.target" ];
      };
    }
  );
}
