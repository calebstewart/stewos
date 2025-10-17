{ ... }:
{ lib, ... }:
{
  networking = {
    # Enable NetworkManager for manaing network connections
    networkmanager.enable = lib.mkDefault true;

    # Enable the firewall
    firewall = {
      enable = lib.mkDefault true;
      logReversePathDrops = lib.mkDefault true;
    };
  };

  # Enable bluetooth support
  hardware.bluetooth.enable = lib.mkDefault true;
}
