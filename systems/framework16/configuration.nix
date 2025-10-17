{ nixos-hardware, ... }@inputs:
{ pkgs, lib, ... }:
rec {
  imports = [
    nixos-hardware.nixosModules.framework-16-7040-amd
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
      command = lib.getExe pkgs.hyprland;
    };
  };

  # Set the system hostname
  networking.hostName = "framework16";

  # Enable embedded home-manager
  home-manager.users.${stewos.user.username} = import ./home.nix inputs;

  # Some tweaks for this specific hardware
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # This prevents hibernation
  security.protectKernelImage = false;

  # Setup systemd sleep configuration
  systemd.sleep.extraConfig = ''
    AllowHybridSleep=yes
    AllowSuspend=yes
    AllowHibernate=yes
  '';
}
