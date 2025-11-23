{ nixos-hardware, ... }:
{ pkgs, config, ... }:
let
  user = config.stewos.user;
in
{
  imports = [
    nixos-hardware.nixosModules.framework-16-7040-amd
  ];

  stewos = {
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
      enableDockerCompatibility = true;
    };

    autologin = {
      enable = true;
      username = user.username;
      command = "${config.users.users.${user.username}.home}/.wayland-session";
    };
  };

  # Set the system hostname
  networking.hostName = "framework16";

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
