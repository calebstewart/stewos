{ ... }:
{
  lib,
  config,
  pkgs,
  ...
}:
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
    home.packages = [ pkgs.ripgrep ];

    programs.git = {
      enable = true;

      ignores = [
        ".envrc"
        ".direnv"
      ];

      settings = {
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        gpg.format = "ssh";
        commit.gpgsign = true;

        user = {
          email = config.stewos.user.email;
          name = config.stewos.user.fullname;
          signingkey = "${config.home.homeDirectory}/.ssh/id_ed25519";
        };

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
          name = lib.attrsets.attrByPath [ "fullname" ] config.stewos.user.fullname alias;
        };
      }) config.stewos.user.aliases;
    };
  };
}
