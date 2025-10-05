{lib, config, pkgs, ...}:
let
  cfg = config.stewos.firefox;
in {
  options.stewos.firefox.enable = lib.mkEnableOption "firefox";

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;

      profiles.${config.home.username} = {
        isDefault = true;
        containersForce = true;

        settings = {
          "browser.theme.content-theme" = 2;
          "browser.startup.homepage" = "https://www.google.com";
          "ui.systemUsesDarkTheme" = 1;
        };

        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          lastpass-password-manager
          ublock-origin
          cookie-quick-manager
          multi-account-containers
        ];

        search = {
          default = "google";
          order = ["google" "Nix Packages"];
          privateDefault = "google";
          force = true;

          engines = {
            "Nix Packages" = {
              urls = [{
                template = "https://search.nixos.org/packages";
                params = [
                  { name = "type"; value = "packages"; }
                  { name = "query"; value = "{searchTerms}"; }
                ];
              }];

              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@np" ];
            };

            "bing".metaData.hidden = true;

            "google".metaData.alias = "@g";
          };
        };

        containers = {
          Personal = {
            color = "blue";
            icon = "fingerprint";
            id = 1;
          };

          Work = {
            color = "orange";
            icon = "briefcase";
            id = 2;
          };
        };
      };
    };
  };

}

