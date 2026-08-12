# The macOS desktop: Aerospace for tiling, Raycast as the launcher, Karabiner
# for the keyboard, and AutoRaise for focus-follows-mouse.
#
# Every file here guards its own config on "cfg.enable && isDarwin" rather than
# being imported conditionally, because deciding what to import from
# pkgs.stdenv risks a recursion the module system cannot see through.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
in
{
  imports = [
    ./aerospace.nix
    ./karabiner.nix
    ./autoraise.nix
    ./raycast.nix
  ];

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    assertions = [
      {
        assertion = cfg.monitors == [ ];
        message = ''
          stewos.desktop.monitors is not supported on macOS, which arranges
          displays itself. Use System Settings > Displays.
        '';
      }
      {
        assertion = cfg.keyboards == { };
        message = ''
          stewos.desktop.keyboards is not supported on macOS: Karabiner matches
          keyboards by vendor and product identifier rather than by name.
        '';
      }
      {
        assertion = !cfg.startLocked;
        message = "stewos.desktop.startLocked is only implemented on Linux.";
      }
    ];

    home.activation.setDarwinWallpaper =
      let
        osascript = "/usr/bin/osascript";
        scriptFile = pkgs.writeTextFile {
          name = "set-wallpaper.osa";
          text = ''
            tell application "System Events"
              tell every desktop
                set picture to "${cfg.wallpaper}"
              end tell
            end tell
          '';
        };
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.strings.escapeShellArgs [
          osascript
          scriptFile
        ]
      );
  };
}
