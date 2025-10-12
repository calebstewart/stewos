{nixos-hardware, lanzaboote, ...}@inputs:
{pkgs, lib, config, ...}: rec {
  imports = [
    nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    lanzaboote.nixosModules.lanzaboote
  ];

  stewos = rec {
    audio.enable = true;
    desktop-services.enable = true;
    greeter.enable = false;
    zsa.enable = false;
    virtualisation.enable = true;
    sshd.enable = true;
    looking-glass.enable = false;

    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatability = true;
    };

    user = {
      username = "caleb";
      fullname = "Caleb Stewart";
    };

    autologin = {
      enable = true;
      username = user.username;
      command = "${config.users.users.${user.username}.home}/.wayland-session";
    };
  };

  boot = {
    # Disable in favor of Lanzaboote for Secure Boot
    loader.systemd-boot.enable = lib.mkForce false;
    loader.systemd-boot.editor = false;
    loader.timeout = 0;

    # Enable Lanzaboote for Secure Boot support
    lanzaboote.enable = true;
    lanzaboote.pkiBundle = "/var/lib/sbctl";

    # Some tweaks for this specific hardware
    kernelPackages = pkgs.linuxPackages_latest;

    # Silent boot stuff
    kernelParams = ["quiet" "splash" "loglevel=3" "systemd.show_status=auto" "rd.udev.log_level=3" "udev.log_level=3"];

    # Disable logging
    consoleLogLevel = 0;
    initrd.verbose = false;
  };


  # Set the system hostname
  networking.hostName = "framework-desktop";

  # Enable embedded home-manager
  home-manager.users.${stewos.user.username} = import ./home.nix inputs;
  
  # I thought this was needed, but it seems that the config is already set by default
  # boot.kernelPatches = lib.singleton {
  #   name = "enable_fbcon_deferred_takeover";
  #   patch = null;
  #   extraStructuredConfig = with lib.kernel; {
  #     FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER = yes;
  #   };
  # };

  # This prevents hibernation
  security.protectKernelImage = false;

  # Setup systemd sleep configuration
  systemd.sleep.extraConfig = ''
    AllowHybridSleep=yes
    AllowSuspend=yes
    AllowHibernate=yes
  '';

  # Install extra packages
  environment.systemPackages = [pkgs.sbctl];
}

