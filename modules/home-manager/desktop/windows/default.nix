# The Windows desktop: komorebi for tiling, whkd for the keys, YASB for the
# bar and, through its Quick Launch widget, the launcher (./yasb.nix), and
# masir for focus-follows-mouse, all run by steward (./services.nix). All of
# it is winpkgs' (github:calebstewart/winpkgs), which evaluates a Windows home
# against home-manager's own modules plus its own -- YASB's module aside, which
# is StewOS's (../../yasb.nix), written to move there.
#
# komorebi-bar and Flow Launcher, which YASB replaces, are off. A host that
# turns Flow back on (programs.flow-launcher.enable) gets the "launcher"
# binding back as well; see ./bindings.nix.
#
# Every file here guards its own config on "cfg.enable && isWindows", as the
# Linux and macOS backends do, and on one thing more: that winpkgs' options
# exist at all. programs.komorebi, programs.whkd and windows.* are declared
# only in a winpkgs home, and a definition of an undeclared option is an error
# even under a false mkIf, so without it the Linux and macOS homes would not
# evaluate. The guard tests `options` rather than `pkgs`: the shape of a
# module's config may depend on which options exist, but deciding it from pkgs
# risks the same recursion the unconditional imports are there to avoid.
{
  options,
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
    ./komorebi.nix
    ./yasb.nix
    ./bindings.nix
    ./theme.nix
    ./services.nix
  ];

  config = lib.optionalAttrs (options ? windows) (
    lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isWindows) {
      assertions = [
        {
          assertion = cfg.monitors == [ ];
          message = ''
            stewos.desktop.monitors is not supported on Windows, which arranges
            displays itself. Use Settings > System > Display.
          '';
        }
        {
          assertion = cfg.keyboards == { };
          message = ''
            stewos.desktop.keyboards is not supported on Windows, which has no
            per-device keyboard settings a home configuration can reach.
          '';
        }
        {
          assertion = !cfg.startLocked;
          message = "stewos.desktop.startLocked is only implemented on Linux.";
        }
        {
          assertion = !cfg.capsLockEscape;
          message = ''
            stewos.desktop.capsLockEscape cannot be done from a Windows home:
            the only remapping Windows has is the machine-wide scancode map. Set
            windows.keyboard.remap.CapsLock = "Escape" in the host's system
            configuration (configuration.nix) instead.
          '';
        }
      ];

      # Focus follows the mouse; masir only focuses windows komorebi manages.
      programs.masir.enable = lib.mkDefault true;
    }
  );
}
