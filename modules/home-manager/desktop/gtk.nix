{pkgs, lib, config, ...}:
let
  cfg = config.stewos.desktop;
in {
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    gtk = {
      enable = true;

      cursorTheme = {
        name = "catppuccin-mocha-dark-cursors";
        package = pkgs.catppuccin-cursors.mochaDark;
      };

      theme = {
        name = "catppuccin-mocha-blue-standard";
        package = pkgs.catppuccin-gtk.override {
          variant = "mocha";
          accents = ["blue"];
        };
      };
      
      iconTheme = {
        name = "Papirus";
        package = pkgs.catppuccin-papirus-folders.override {
          flavor = "mocha";
          accent = "blue";
        };
      };
    };

    # Double-check that the cursor is set properly (it's finicky)
    home.pointerCursor = {
      gtk.enable = true;
      name = "catppuccin-mocha-dark-cursors";
      package = pkgs.catppuccin-cursors.mochaDark;
    };

    # Dark mode is best mode
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    }; 
  };
}
