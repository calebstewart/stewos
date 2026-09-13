{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.zsh;
in
{
  options.stewos.zsh = {
    enable = lib.mkEnableOption "zsh";
  };

  config = lib.mkIf cfg.enable {
    # The prompt is the shared module (see oh-my-posh.nix); home-manager's
    # programs.oh-my-posh hooks it into the shell below.
    stewos.oh-my-posh.enable = lib.mkDefault true;

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      shellAliases = {
        vim = "nvim";
      };

      initContent =
        let
          any-nix-shell-init = lib.escapeShellArgs [
            (lib.getExe pkgs.any-nix-shell)
            "zsh"
            "--info-right"
          ];
        in
        lib.mkMerge [
          # any-nix-shell sets RPROMPT from its own precmd; it has to be
          # initialised before oh-my-posh's hook, which home-manager adds at
          # the default order (1000).
          (lib.mkOrder 900 ''
            ${any-nix-shell-init} | source /dev/stdin
          '')
          ''
            if [[ -t 0 && $- = *i* ]]; then
              stty -ixon
            fi
          ''
        ];

      plugins = [ ];
    };
  };
}
