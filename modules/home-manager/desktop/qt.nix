{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    # Have QT match GTK
    qt = {
      enable = true;
      platformTheme.name = "gtk";
    };
  };
}

