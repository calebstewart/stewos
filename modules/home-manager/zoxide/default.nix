{ ... }:
{ lib, config, ... }:
let
  cfg = config.stewos.zoxide;
in
{
  options.stewos.zoxide.enable = lib.mkEnableOption "zoxide";

  config = lib.mkIf cfg.enable {
    programs.zoxide = {
      enable = true;
      enableZshIntegration = false;

      options = [
        "--cmd"
        "cd"
      ];
    };

    programs.zsh.initContent =
      let
        zoxide = config.programs.zoxide.package;
        options = lib.concatStringsSep " " config.programs.zoxide.options;
      in
      lib.mkOrder 851 ''
        if [[ "$CLAUDECODE" != "1" ]]; then
          eval "$(${lib.getExe zoxide} init zsh ${options} )"
        fi
      '';
  };
}
