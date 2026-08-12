{ lib, ... }:
{
  config = {
    # We do not use sudo
    security.sudo.enable = false;

    # Configure doas to allow the administrators
    security.doas.enable = true;

    # Enable polkit
    security.polkit = {
      enable = true;
      extraConfig = lib.mkForce "";
    };
  };
}
