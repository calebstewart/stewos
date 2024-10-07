{pkgs, ...}: {
  home.packages = with pkgs; [
    jetbrains-mono
    roboto
    openmoji-color
    (nerdfonts.override {
      fonts = ["JetBrainsMono"];
    })
  ];
  
  fonts.fontconfig = {
    enable = true;
    defaultFonts.emoji = ["OpenMoji Color"];
  };
}
