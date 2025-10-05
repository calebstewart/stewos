{...}:
{lib, config, ...}:
let
  cfg = config.stewos.zoxide;
in {
  options.stewos.zoxide.enable = lib.mkEnableOption "zoxide";

  config = lib.mkIf cfg.enable {
    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;

      options = [
        "--cmd" "cd"
      ];
    };
  };
}

