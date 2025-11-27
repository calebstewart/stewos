{
  pkgs,
  config,
  ...
}:
let
  user = config.stewos.user;
in
{
  # All stewos-specific configuration is under the top-level `stewos` field
  stewos = {
    # Configure system services/packages needed for a graphical desktop
    desktop-services.enable = true;
    audio.enable = true;

    # Setup libvirtd
    virtualisation.enable = true;

    # Setup an SSH server
    sshd.enable = true;

    # Setup podman for containers w/ compose support
    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatibility = true;
    };

    # Disable the graphical greeter
    greeter.enable = false;

    # Automatically login the default user
    autologin = {
      enable = true;
      username = user.username;
      command = "${config.users.users.${user.username}.home}/.wayland-session";
    };
  };

  # Also, any other system-level configuration you want.
  # For example, install a package.
  environment.systemPackages = [ pkgs.python3 ];
}
