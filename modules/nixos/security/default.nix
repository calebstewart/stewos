{ ... }:
{ ... }:
{
  config = {
    # We do not use sudo
    security.sudo.enable = false;

    # Configure doas to allow the administrators
    security.doas.enable = true;

    # Allow hyprlock to unlock the system
    security.pam.services.hyprlock = { };
  };
}
