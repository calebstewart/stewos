{ ... }:
{ lib, config, ... }:
let
  cfg = config.stewos.git;
in
{
  options.stewos.git = {
    enable = lib.mkEnableOption "git";
    forceSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;

      userName = config.stewos.user.fullName;
      userEmail = config.stewos.user.email;

      ignores = [
        ".envrc"
        ".direnv"
      ];

      extraConfig = {
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        gpg.format = "ssh";
        commit.gpgsign = true;
        user.signingkey = "${config.home.homeDirectory}/.ssh/id_ed25519";

        url = lib.mkIf cfg.forceSSH {
          "git@github.com:" = {
            insteadOf = "https://github.com/";
          };
        };
      };

      includes = lib.attrsets.mapAttrsToList (name: alias: {
        condition = "gitdir:~/git/${name}";
        contents.user = {
          email = lib.attrsets.attrByPath [ "email" ] config.stewos.user.email alias;
          name = lib.attrsets.attrByPath [ "fullName" ] config.stewos.user.fullName alias;
        };
      }) config.stewos.user.aliases;
    };
  };
}
