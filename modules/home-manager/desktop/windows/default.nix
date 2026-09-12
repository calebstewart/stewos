# The Windows desktop: komorebi for tiling, whkd for the keys, Flow Launcher
# as the launcher, and masir for focus-follows-mouse. All of it is winpkgs'
# (github:calebstewart/winpkgs), which evaluates a Windows home against
# home-manager's own modules plus its own.
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
    ./bindings.nix
    ./theme.nix
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

      # The launcher the "launcher" action summons. Flow is single-instance,
      # so starting it again shows the running one, which is how whkd calls it
      # up without the two fighting over a global hotkey.
      programs.flow-launcher.enable = lib.mkDefault true;

      # Focus follows the mouse; masir only focuses windows komorebi manages.
      programs.masir.enable = lib.mkDefault true;
    }
  );
}
