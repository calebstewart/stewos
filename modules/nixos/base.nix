# Defaults every StewOS machine is expected to want: boot loader, Nix settings,
# documentation, and the handful of programs that are assumed to exist.
#
# This lives behind an option rather than being unconditional so that importing
# stewos.nixosModules.default does not silently hand you a boot loader. Set
# stewos.base.enable = false to take the modules without the opinions.
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.base;
in
{
  options.stewos.base.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Apply the opinionated StewOS system defaults.";
  };

  config = lib.mkIf cfg.enable {
    # Setup Nix configuration
    nix = {
      settings.auto-optimise-store = true;
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    boot = {
      # Clean tmpfs during system boot
      tmp.cleanOnBoot = true;

      # Use systemd-boot
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      # Use a pretty spinner animation for the boot process
      plymouth = {
        enable = true;
        theme = "spin";
        themePackages = [
          (pkgs.adi1090x-plymouth-themes.override {
            selected_themes = [ "spin" ];
          })
        ];
      };
    };

    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    # Setup Nix Helper for easy building
    programs.nh = {
      enable = true;
      package = inputs.nh.packages.${pkgs.stdenv.hostPlatform.system}.default;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 5";
    };

    # This is needed or else home-manager fails to start later
    programs.dconf.enable = true;

    # Enable mandb and nix documentation
    documentation = {
      enable = true;

      man = {
        enable = true;
        cache.enable = true;
      };
    };
  };
}
