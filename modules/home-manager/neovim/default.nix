# Neovim, configured the ordinary way. The Lua under ./config *is* the
# configuration, shipped verbatim to NixOS, nix-darwin and winpkgs; plugins are
# lazy.nvim's. Nix contributes exactly two things: the tools on Neovim's PATH
# (language servers, ripgrep, a C compiler, node) and
# lua/stewos/generated.lua, carrying the colour palette and this machine's
# server list. Never a store path -- that is what lets the same directory work
# on Windows, where there is no store and mason installs the servers instead.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stewos.neovim;
  isWindows = pkgs.stdenv.hostPlatform.isWindows;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # nvim-lspconfig name -> the nixpkgs package that provides the executable.
  # lua/stewos/platform.lua holds the mason name for the same servers.
  serverPackages = {
    lua_ls = pkgs.lua-language-server;
    gopls = pkgs.gopls;
    nixd = pkgs.nixd;
    pyright = pkgs.pyright;
    clangd = pkgs.clang-tools;
    jdtls = pkgs.jdt-language-server;
    ts_ls = pkgs.typescript-language-server;
    vala_ls = pkgs.vala-language-server;
    mesonlsp = pkgs.mesonlsp;
    qmlls = pkgs.qt6.qtdeclarative;
    ruby_lsp = pkgs.ruby-lsp;
    rust_analyzer = pkgs.rust-analyzer;
    gh_actions_ls = pkgs.stewos.gh-actions-language-server;
  };

  # No Windows build, or no point without Nix.
  notOnWindows = [
    "nixd"
    "vala_ls"
    "mesonlsp"
    "qmlls"
    "gh_actions_ls"
  ];

  enabledServers = lib.attrNames (lib.filterAttrs (_: on: on) cfg.servers);

  generated = {
    palette = config.colorScheme.palette;
    servers = enabledServers;
    mason = isWindows;
  };

  tools =
    with pkgs;
    [
      ripgrep
      fd
      nixfmt
      nodejs # markdown-preview builds its server with it
      gnumake # telescope-fzf-native
      tree-sitter # nvim-treesitter (main) builds parsers with the CLI ...
      (if isLinux then gcc else clang) # ... and a C compiler
    ]
    ++ lib.optional isLinux wl-clipboard;
in
{
  options.stewos.neovim = {
    enable = lib.mkEnableOption "neovim";

    servers = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = lib.genAttrs (lib.attrNames serverPackages) (
        name: !(isWindows && lib.elem name notOnWindows)
      );
      defaultText = lib.literalMD "every known server; on Windows, minus those without a build there";
      example = {
        mesonlsp = false;
      };
      description = ''
        Language servers to install and enable, by nvim-lspconfig name. Nix
        installs the package on NixOS and macOS; mason installs it on Windows.
        A host turns one off with `stewos.neovim.servers.<name> = false`.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."nvim" = {
          source = ./config;
          recursive = true;
        };
        xdg.configFile."nvim/lua/stewos/generated.lua".text =
          "return " + lib.generators.toLua { } generated;

        home.sessionVariables.EDITOR = "nvim";
      }

      (lib.mkIf (!isWindows) {
        programs.neovim = {
          enable = true;
          withRuby = false;
          withPython3 = false; # no provider plugins; also home-manager's post-26.05 default
          extraPackages = tools ++ map (name: serverPackages.${name}) enabledServers;
        };
      })

      (lib.mkIf isWindows {
        # winget. Servers come through mason; treesitter builds its parsers
        # with the tree-sitter CLI and clang from LLVM, whose installer does
        # not touch PATH. No make, so telescope-fzf-native is skipped and
        # telescope uses its Lua sorter.
        home.packages = with pkgs; [
          neovim
          ripgrep
          fd
          nodejs
          (winpkgs.fromWinget "tree-sitter.tree-sitter-cli")
          (winpkgs.fromWinget "LLVM.LLVM")
        ];
        home.sessionPath = [ ''C:\Program Files\LLVM\bin'' ];
      })
    ]
  );
}
