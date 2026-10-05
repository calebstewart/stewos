# stewctl on the machine, and /etc/stewctl/os.json saying which configuration
# the machine is.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.stewctl;
in
{
  imports = [ ../common/stewctl.nix ];

  config = lib.mkIf cfg.enable {
    stewos.stewctl = {
      # nh's flake may be a path; stewctl records a string.
      flake = lib.mkDefault (
        if config.programs.nh.flake == null then null else toString config.programs.nh.flake
      );
      attribute = lib.mkDefault config.networking.hostName;
    };

    environment.systemPackages = [ pkgs.stewos.stewctl ];

    environment.etc."stewctl/os.json".text = builtins.toJSON {
      inherit (cfg) flake attribute;
      platform = "nixos";
    };
  };
}
