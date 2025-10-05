{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      jetbrains-mono
      roboto
      openmoji-color
      nerd-fonts.jetbrains-mono
    ];
    
    fonts.fontconfig = {
      enable = true;
      defaultFonts.emoji = ["OpenMoji Color"];
    };
  };
}
