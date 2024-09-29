{lib, config, pkgs, ...}:
let
  cfg = config.modules.containers;
in {
  options.modules.containers = {
    enable = lib.mkEnableOption "containers";
    enableCompose = lib.mkEnableOption "compose";
    enableDockerCompatability = lib.mkEnableOption "docker compatability";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      dockerCompat = cfg.enableDockerCompatability;
      dockerSocket.enable = cfg.enableDockerCompatability;
      
      extraPackages = lib.lists.optional cfg.enableCompose (with pkgs; [
        podman-compose
      ]);

      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    virtualisation.containers = {
      enable = true;

      containersConf.cniPlugins = lib.lists.optional cfg.enableCompose (with pkgs; [
        cni-plugins
        dnsname-cni
      ]);
    };
  };
}
