{pkgs, lib, config, nix-std, ...}:
let
  cfg = config.stewos.zsh;
in {
  options.stewos.zsh = {enable = lib.mkEnableOption "zsh";};

  config = lib.mkIf cfg.enable {

    xdg.configFile."ohmyposh/config.toml".text = nix-std.lib.serde.toTOML {
      "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
      final_space = true;
      version = 2;

      blocks = [
        {
          type = "prompt";
          alignment = "left";
          newline = true;

          segments = [
            {
              type = "path";
              style = "plain";
              template = "{{ .Path }}";
              background = "transparent";
              foreground = "blue";
              properties = {
                style = "agnoster_short";
                max_depth = 3;
                folder_icon = "";
                home_icon = "󰜥";
                cycle = ["blue" "lightBlue" "magenta" "lightMagenta"];
              };
            }
            {
              type = "git";
              style = "plain";
              foreground = "darkGray";
              background = "transparent";
              template = " {{ .HEAD }}{{ if or (.Working.Changed) (.Staging.Changed) }}*{{ end }} <cyan>{{ if gt .Behind 0 }}⇣{{ end }}{{ if gt .Ahead 0 }}⇡{{ end }}</>";

              properties = {
                branch_icon = "";
                commit_icon = "@";
                fetch_status = true;
              };
            }
          ];
        }
        {
          type = "rprompt";
          overflow = "hidden";

          segments = [
            {
              type = "executiontime";
              style = "plain";
              foreground = "yellow";
              background = "transparent";
              template = "⏱ {{ .FormattedMs }}";
              properties.threshold = 5000;
            }
          ];
        }
        {
          type = "prompt";
          alignment = "left";
          newline = true;

          segments = [
            {
              type = "text";
              style = "plain";
              template = "❯";
              background = "transparent";
              foreground_templates = [
                "{{ if gt .Code 0 }}red{{ end }}"
                "{{ if eq .Code 0 }}magenta{{ end }}"
              ];
            }
          ];
        }
      ];

      secondary_prompt = {
        foreground = "magenta";
        background = "transparent";
        template = "❯❯ ";
      };

      transient_prompt = {
        template = "❯ ";
        background = "transparent";
        foreground_templates = [
          "{{ if gt .Code 0 }}red{{ end }}"
          "{{ if eq .Code 0 }}magenta{{ end }}"
        ];
      };
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      shellAliases = {
        vim = "nvim";
      };

      # Initialize any-nix-shell during zsh startup
      initContent = ''
        ${pkgs.any-nix-shell}/bin/any-nix-shell zsh --info-right | source /dev/stdin

        # Initialize Oh-My-Posh prompt with above configuration
        eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config "$HOME/.config/ohmyposh/config.toml")"

        if [[ -t 0 && $- = *i* ]]; then
          stty -ixon
        fi
      '';

      plugins = [];
    };
  };
}

