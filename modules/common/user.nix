# Identity of the machine's primary user.
#
# This declares options only. Both the NixOS tree and the home-manager tree
# import it, so the system half and the user half of a machine agree on one
# definition of who the machine is for, without either owning it.
{ lib, config, ... }:
{
  options.stewos.user = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "Login name of the primary user.";
    };

    fullname = lib.mkOption {
      type = lib.types.str;
      description = "Human-readable name, used for the account description and git.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      description = "Primary email address, used as the default git identity.";
    };

    aliases = lib.mkOption {
      default = { };
      description = ''
        Alternate identities, keyed by the directory under ~/git that they apply
        to. Each one produces a conditional include in the git config.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            fullname = lib.mkOption {
              type = lib.types.str;
              default = config.stewos.user.fullname;
              defaultText = lib.literalExpression "config.stewos.user.fullname";
              description = "Human-readable name committed under this directory.";
            };

            email = lib.mkOption {
              type = lib.types.str;
              default = config.stewos.user.email;
              defaultText = lib.literalExpression "config.stewos.user.email";
              description = "Email address committed under this directory.";
            };
          };
        }
      );
    };

    groups = lib.mkOption {
      description = "Extra groups applied to the primary user (NixOS only).";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
}
