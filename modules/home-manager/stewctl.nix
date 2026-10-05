# ~/.config/stewctl/home.json: which home configuration this is.
#
# On Linux and macOS stewctl itself comes from the system configuration. On
# Windows the home installs it: the checkout lives in the user's profile, and a
# winpkgs system has no StewOS modules to do it from.
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.stewos.stewctl;
  bin = ''%LOCALAPPDATA%\stewctl\bin'';
in
{
  imports = [ ../common/stewctl.nix ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."stewctl/home.json".text = builtins.toJSON (
          lib.filterAttrs (_: v: v != null) { inherit (cfg) flake attribute; }
        );
      }

      # winpkgs' options exist only in a winpkgs home; test `options`, not
      # `pkgs`, as the desktop's Windows backend does.
      (lib.optionalAttrs (options ? windows) {
        # The same checkout the winpkgs command is pointed at. The system
        # configuration records none, so `stewctl os` reads it from here too.
        stewos.stewctl.flake = lib.mkDefault config.winpkgs.cli.flake;

        # `pkgs` is a Windows package set here, without the StewOS overlay.
        windows.files.${bin}.source = "${pkgs.callPackage ../../pkgs/stewctl { }}/bin";
        winpkgs.environment.path = [ bin ];
      })
    ]
  );
}
