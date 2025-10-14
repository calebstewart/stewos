{lib, config, pkgs, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    launchd.agents.autoraise = {
      enable = true;

      config = {
        ProgramArguments = [
          (lib.getExe pkgs.autoraise)
          "-pollMillis" "50"
          "-delay" "1"
          "-focusDelay" "0"
          "-scale" "1.0"
          "-altTaskSwitcher" "true"
          "-ignoreSpaceChanged" "false"
        ];

        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}
