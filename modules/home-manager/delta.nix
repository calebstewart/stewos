{
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.delta;
in
{
  options.stewos.delta.enable = lib.mkEnableOption "delta, a syntax-highlighting pager for git, diff and grep output";

  config = lib.mkIf cfg.enable {
    programs.delta = {
      enable = true;

      # Home-manager's integration writes pager.diff/log/show/blame and
      # interactive.diffFilter into programs.git.iniContent, where they merge
      # with stewos.git's own settings. It defaults to false and warns if left
      # to the deprecated auto-enable, so set it here; keying it off git makes
      # the dependency greppable.
      enableGitIntegration = config.programs.git.enable;

      # Nothing here needs the palette: bat's built-in "base16" theme renders
      # through the terminal's ANSI colours, which alacritty.nix and ghostty.nix
      # set from config.colorScheme. So delta, bat and the terminal follow a
      # scheme change together, on darwin as much as on Linux.
      options = {
        syntax-theme = "base16";
        dark = true;

        line-numbers = true;
        side-by-side = true;
        navigate = true;
        hyperlinks = true;
      };
    };
  };
}
