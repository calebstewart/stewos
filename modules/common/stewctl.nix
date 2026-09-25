# What stewctl needs to know about a configuration: which flake it lives in and
# which attribute of that flake it is.
#
# This declares options only. The NixOS, nix-darwin and home-manager trees each
# import it and write the answer where stewctl looks -- /etc/stewctl/os.json
# from a system, ~/.config/stewctl/home.json from a home -- so that stewctl
# never has to guess a configuration from the hostname.
{ lib, ... }:
{
  options.stewos.stewctl = {
    enable = lib.mkEnableOption "stewctl, the command that builds and switches this configuration" // {
      default = true;
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/caleb/git/stewos";
      description = ''
        Path of the checkout this configuration is built from. On a system it
        defaults to `programs.nh.flake`. A home can leave it `null` to use the
        machine's, then `$NH_FLAKE`, then `~/git/stewos`.
      '';
    };

    attribute = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "framework-desktop";
      description = ''
        The name of this configuration in the flake: the attribute under
        `nixosConfigurations` or `darwinConfigurations` for a system (by
        default the hostname), under `homeConfigurations` for a home
        (`user@host`, set by `mkHome` in `flake.nix`). `null` leaves stewctl
        to guess, as nh does.
      '';
    };
  };
}
