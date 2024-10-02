{lib, config, ...}:
let
  cfg = config.stewos.sshd;
in {
  options.stewos.sshd = {
    enable = lib.mkEnableOption "sshd";

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 22;
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [cfg.port];
      startWhenNeeded = true;
      openFirewall = true;
      listenAddresses = [{addr = cfg.address; port = cfg.port;}];

      settings = {
        UsePAM = false;
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
  };
}
