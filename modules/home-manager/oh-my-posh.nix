# The prompt, shared by every shell StewOS configures: zsh on Linux and macOS
# through home-manager's own oh-my-posh module, PowerShell on Windows through
# winpkgs' programs.powershell, which reads the same `settings` and hooks the
# generated config.json into the profile.
#
# Colours are the nix-colors palette (config.colorScheme), so a scheme change
# moves the prompt with the desktop and the terminals rather than leaving it on
# whatever the terminal maps the ANSI names to.
{
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.oh-my-posh;
  palette = config.colorScheme.palette;
in
{
  options.stewos.oh-my-posh = {
    enable = lib.mkEnableOption "the StewOS Oh-My-Posh prompt, themed from the nix-colors palette";
  };

  config = lib.mkIf cfg.enable {
    programs.oh-my-posh = {
      enable = true;

      settings = {
        "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
        final_space = true;
        version = 2;

        # base16 has no light variants, so the path cycle runs through four
        # distinct accent slots instead of blue/lightBlue/magenta/lightMagenta.
        palette = {
          blue = "#${palette.base0D}";
          cyan = "#${palette.base0C}";
          magenta = "#${palette.base0E}";
          pink = "#${palette.base0F}";
          muted = "#${palette.base03}";
          yellow = "#${palette.base0A}";
          red = "#${palette.base08}";
        };

        blocks = [
          {
            type = "prompt";
            alignment = "left";
            newline = true;

            segments = [
              # Only rendered when the session is root, or elevated on
              # Windows (`sudo pwsh`), so the two otherwise identical prompts
              # can be told apart.
              {
                type = "root";
                style = "plain";
                template = "⚡ ";
                background = "transparent";
                foreground = "p:red";
              }
              {
                type = "path";
                style = "plain";
                template = "{{ .Path }}";
                background = "transparent";
                foreground = "p:blue";
                properties = {
                  style = "agnoster_short";
                  max_depth = 3;
                  folder_icon = "";
                  home_icon = "󰜥";
                  cycle = [
                    "p:blue"
                    "p:cyan"
                    "p:magenta"
                    "p:pink"
                  ];
                };
              }
              {
                type = "git";
                style = "plain";
                foreground = "p:muted";
                background = "transparent";
                template = " {{ .HEAD }}{{ if or (.Working.Changed) (.Staging.Changed) }}*{{ end }} <p:cyan>{{ if gt .Behind 0 }}⇣{{ end }}{{ if gt .Ahead 0 }}⇡{{ end }}</>";

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
                foreground = "p:yellow";
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
                  "{{ if gt .Code 0 }}p:red{{ end }}"
                  "{{ if eq .Code 0 }}p:magenta{{ end }}"
                ];
              }
            ];
          }
        ];

        secondary_prompt = {
          foreground = "p:magenta";
          background = "transparent";
          template = "❯❯ ";
        };

        # The root mark is repeated here so lines already in scrollback still
        # say which session they came from.
        transient_prompt = {
          template = "{{ if .Root }}⚡ {{ end }}❯ ";
          background = "transparent";
          foreground_templates = [
            "{{ if gt .Code 0 }}p:red{{ end }}"
            "{{ if eq .Code 0 }}p:magenta{{ end }}"
          ];
        };
      };
    };
  };
}
