{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.embermug-tray;
in
{
  # The upstream flake ships the package, the systemd unit and the QSettings
  # file; this module only re-exposes them under stewos.*.
  imports = [ inputs.embermug-tray.homeManagerModules.default ];

  options.stewos.embermug-tray = {
    enable = lib.mkEnableOption "the EmberMug tray application";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.embermug-tray.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The embermug-tray package to run.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      description = "Settings written to the embermug-tray QSettings file.";
      example = lib.literalExpression ''
        { device.address = "AA:BB:CC:DD:EE:FF"; }
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    services.embermug-tray = {
      enable = true;
      inherit (cfg) package settings;
    };
  };
}
