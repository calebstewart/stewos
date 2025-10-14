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
    
    fonts.fontconfig = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      defaultFonts.emoji = ["OpenMoji Color"];
    };
  };
}
