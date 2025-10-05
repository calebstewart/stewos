{pkgs, ...}: {
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
}
