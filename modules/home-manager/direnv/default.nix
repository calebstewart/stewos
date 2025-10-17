{ ... }:
{ lib, config, ... }:
let
  cfg = config.stewos.direnv;
in
{
  options.stewos.direnv.enable = lib.mkEnableOption "direnv";

  config = lib.mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;

      config = {
        global.hide_env_diff = true;
      };

      stdlib = ''
        layout_poetry() {
          POETRY_DIR="''${POETRY_DIR:-.}"

          # Verify we have a project
          PYPROJECT_TOML="''${PYPROJECT_TOML:-pyproject.toml}"
          if [[ ! -f "$PYPROJECT_TOML" ]]; then
            log_error "no pyproject.toml found. use \`poetry init\` to create \`$PYPROJECT_TOML\` first."
            exit 2
          fi

          # Lookup the active poetry environment
          VIRTUAL_ENV=$(poetry -C "$POETRY_DIR" env info --path 2>/dev/null ; true)
          if [[ -z $VIRTUAL_ENV || ! -d $VIRTUAL_ENV ]]; then
            log_status "no poetry environment exists."
            log_status "executing \`poetry install\` to create one."
            poetry -C "$POETRY_DIR" install
            VIRTUAL_ENV=$(poetry -C "$POETRY_DIR" env info --path)
          fi

          # Activate the environment. We don't use 'poetry shell' because that
          # spawns a subshell. Instead, we manually activate the environment by
          # adding the bin directory to our path, and setting VIRTUAL_ENV.
          log_status "using poetry environment: $VIRTUAL_ENV"
          PATH_add "$VIRTUAL_ENV/bin"
          export POETRY_ACTIVE=1  # or VENV_ACTIVE=1
          export VIRTUAL_ENV
        }

        use_ruby() {
          local ruby_dir=$HOME/.rubies/ruby-$1
          load_prefix $ruby_dir
          layout ruby
        }
      '';
    };
  };
}
