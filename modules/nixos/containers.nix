{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.containers;
in
{
  options.stewos.containers = {
    enable = lib.mkEnableOption "containers";
    enableCompose = lib.mkEnableOption "compose";
    enableDockerCompatibility = lib.mkEnableOption "docker compatability";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;

      rootless = {
        enable = true;
        setSocketVariable = true;
      };

      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    virtualisation.containers = {
      enable = true;

      containersConf.cniPlugins = with pkgs; [
        cni-plugins
        dnsname-cni
      ];
    };
  };
}
