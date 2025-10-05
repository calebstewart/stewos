{...}:
{pkgs, lib, config, ...}:
let
  cfg = config.stewos.zsa;
  zsa-rules = pkgs.writeTextFile {
    name = "zsa-udev-rules";
    text = ./zsa.rules;
    destination = "/etc/udev/rules.d/50-zsa.rules";
  };
in {
  options.stewos.zsa.enable = lib.mkEnableOption "zsa";

  config = lib.mkIf cfg.enable {
    # Install udev rules for ZSA keyboards 
    services.udev.enable = true;
    services.udev.packages = [zsa-rules];

    # Install the keyampp application for editing layouts
    environment.systemPackages = with pkgs; [
      keymapp
    ];
  };
}
