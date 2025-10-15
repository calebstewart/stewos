{nixvim, ...}:
{lib, config, pkgs, ...}:
let
  cfg = config.stewos.neovim;
in {
  options.stewos.neovim.enable = lib.mkEnableOption "neovim";

  imports = [nixvim.homeModules.nixvim];

  config = lib.mkIf cfg.enable {

    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      withRuby = false; 

      globals = {
        # The global leader is " ", which behaves similarly to emacs shortcuts
        mapleader = " ";

        # Default to a transparent background through transparent.nvim
        transparent_enabled = true;
      };

      # Neovim options
      opts = {
        number = true;
        relativenumber = true;
        expandtab = true;
        termguicolors = true;
        shiftwidth = 2;
        tabstop = 2;
        softtabstop = 2;

        ignorecase = true;
        smartcase = true;
        signcolumn = "yes";
        cursorline = true;
        ruler = true;
      };

      # Use whatever color scheme was selected for the system. This is
      # normally just a nix-colors base16 palette, which means we could
      # set base16.colorscheme to config.colorScheme.slug, but in the
      # event we use a non-standard base16 scheme, that will fail.
      # instead, we set the scheme manually.
      colorschemes.base16 = {
        enable = true;

        colorscheme = with config.colorScheme.palette; {
          base00 = "#${base00}";
          base01 = "#${base01}";
          base02 = "#${base02}";
          base03 = "#${base03}";
          base04 = "#${base04}";
          base05 = "#${base05}";
          base06 = "#${base06}";
          base07 = "#${base07}";
          base08 = "#${base08}";
          base09 = "#${base09}";
          base0A = "#${base0A}";
          base0B = "#${base0B}";
          base0C = "#${base0C}";
          base0D = "#${base0D}";
          base0E = "#${base0E}";
          base0F = "#${base0F}";
        };
      };

      # Enable cliboard support with the default register
      clipboard = {
        providers.wl-copy.enable = pkgs.stdenv.isLinux;
        register = "unnamedplus";
      };

      # Enable common plugins with no extra configuration
      plugins = {
        nix.enable = true;
        # bufferline.enable = true;
        lualine.enable = true;
        lsp-format.enable = true;
        oil.enable = true;
        cmp-nvim-lsp-signature-help.enable = true;
        transparent.enable = true;
        noice.enable = true;
        neogit.enable = true;
        vim-bbye.enable = true;
        illuminate.enable = true;
        web-devicons.enable = true;
      };

      plugins.treesitter = {
        enable = true;
        settings.highlight.enable = true;
        languageRegister.hcl = ["hcl" "tf" "terraform"];
      };

      plugins.markdown-preview = {
        enable = true;

        settings = {
          auto_start = 0;
          auto_close = 1;
          browserfunc = "OpenBrowser";
        };
      };

      plugins.trouble = {
        enable = true;
      };

      # Fancy notifications within neovim
      plugins.notify = {
        enable = true;

        # NOTE: british spelling :sob:
        settings.background_colour = "#${config.colorScheme.palette.base01}";
      };

      # Toggle-able terminal emulators within Neovim!
      plugins.toggleterm = {
        enable = true;

        settings = {
          direction = "horizontal";
          hide_numbers = true;
        };
      };

      plugins.lspsaga = {
        enable = true;
        settings.devicon = true;
      };

      # Setup Language Servers
      plugins.lsp = {
        enable = true;

        servers = {
          lua_ls.enable = true;
          gopls.enable = true;
          nixd.enable = true;
          pyright.enable = true;
          clangd.enable = true;
          jdtls.enable = true;
          ts_ls.enable = true;
          vala_ls.enable = true;
          mesonlsp.enable = true;

          ruby_lsp = {
            enable = true;
            packageFallback = true;
          };

          rust_analyzer = {
            enable = true;
            installRustc = false;
            installCargo = false;
          };

          gh_actions_ls = {
            enable = true;
            package = pkgs.gh-actions-language-server;
          };
        };

        keymaps.extra = [
          {
            key = "<leader>lx";
            action = "<CMD>LspStop<Enter>";
            options.desc = "Stop LSP Server";
          }
          {
            key = "<leader>ls";
            action = "<CMD>LspStart<Enter>";
            options.desc = "Start LSP Server";
          }
          {
            key = "<leader>lr";
            action = "<CMD>LspRestart<Enter>";
            options.desc = "Restart LSP Server";
          }
          {
            key = "<leader>ll";
            action = "<CMD>Lspsaga show_line_diagnostics<Enter>";
            options.desc = "Show Line Diagnostics";
          }
          {
            key = "<leader>gd";
            action = "<cmd>Telescope lsp_definitions<CR>";
            options.desc = "Go to Definition";
          }
          {
            key = "<leader>gt";
            action = "<cmd>Telescope lsp_type_definitions<CR>";
            options.desc = "Go to Type Definition";
          }

          {
            key = "<leader>gi";
            action = "<cmd>Telescope lsp_implementations<CR>";
            options.desc = "Go to Implementation";
          }

          {
            key = "<leader>fi";
            action = "<cmd>Telescope lsp_incoming_calls<CR>";
            options.desc = "Find Incoming Calls";
          }
          {
            key = "<leader>fo";
            action = "<cmd>Telescope lsp_outgoing_calls<CR>";
            options.desc = "Find Outgoing Calls";
          }
          {
            key = "<leader>fr";
            action = "<cmd>Telescope lsp_references<CR>";
            options.desc = "Find References";
          }
          {
            key = "K";
            action = "<CMD>Lspsaga hover_doc<Enter>";
          }
          {
            key = "<leader>la";
            action = "<cmd>Lspsaga code_action<CR>";
            options.desc = "View Code Actions";
          }
          {
            key = "<leader>lr";
            action = "<cmd>lua vim.lsp.buf.rename()<CR>";
            options.desc = "Rename Current Symbol";
          }
        ];
      };

      # Setup auto-completion
      plugins.cmp = {
        enable = true;
        autoEnableSources = true;

        settings.sources = [
          {name = "nvim_lsp";}
          {name = "path";}
          {name = "buffer";}
        ];
      };

      # Setup none-ls for LSP features from external tools
      plugins.none-ls = {
        enable = true;
        enableLspFormat = true;
      };

      # Install telescope because it's pretty :)
      plugins.telescope = {
        enable = true;

        extensions = {
          fzf-native.enable = true;
        };
      };

      # Setup neotree for a file browser bar
      plugins.neo-tree = {
        enable = true;

        settings = {
          enable_diagnostics = true;
          enable_git_status = true;
          enable_modified_markers = true;
          enable_refresh_on_write = true;
          close_if_last_window = true;
          popup_border_style = "rounded";
          window.mappings."<space>" = "none";
          filesystem.filtered_items.always_show = [".github" ".circleci"];
        };

      };

      plugins.which-key = {
        enable = true;

        settings.spec = lib.foldlAttrs (acc: key: desc: acc ++ [{
          inherit desc;
          __unkeyed-1 = key;
        }]) [] {
          "<leader>w" = "Windows...";
          "<leader>b" = "Buffers...";
          "<leader>o" = "Open Tools...";
          "<leader>g" = "Go to...";
          "<leader>f" = "Find...";
        };
      };

      extraConfigVim = ''
        sign define DiagnosticSignError text= texthl=TextError linehl= numhl=
        sign define DiagnosticSignWarn  text= texthl=TextWarn  linehl= numhl=
        sign define DiagnosticSignInfo  text= texthl=TextInfo  linehl= numhl=
        sign define DiagnosticSignHint  text= texthl=TextHint  linehl= numhl=

        function OpenBrowser(url)
          execute "silent ! firefox --new-window " . a:url
        endfunction
      '';

      extraConfigLua = ''
        vim.api.nvim_set_hl(0, "IlluminatedWordText", { link = "Visual" })
        vim.api.nvim_set_hl(0, "IlluminatedWordRead", { link = "Visual" })
        vim.api.nvim_set_hl(0, "IlluminatedWordWrite", { link = "Visual" })
      '';

      autoCmd = [
        {
          event = ["BufEnter" "BufWinEnter"];
          pattern = "*.md";
          desc = "Setup Markdown-Specific Keymaps";
          callback.__raw = ''
            function()
              vim.schedule(function()
                vim.keymap.set("n", "<leader>op", "<cmd>MarkdownPreview<CR>", {buffer = true})
              end)
            end
          '';
        }
        {
          event = ["VimEnter"];
          pattern = "*";
          desc = "Open current directory if no argument is given";
          command = ''
            if argc() == 0 | :Oil | endif
          '';
        }
      ];

      keymaps = [
        {
          key = "<leader>ff";
          action = "<cmd>Telescope git_files<CR>";
          options.desc = "Find Project File";
        }

        {
          key = "<leader>of";
          action = "<cmd>Neotree toggle<CR>";
          options.desc = "Toggle NeoTree Explorer";
        }

        {
          key = "<leader>ot";
          action = "<cmd>ToggleTerm<CR>";
          options.desc = "Toggle Terminal";
        }

        {
          key = "<leader>og";
          action = "<cmd>Neogit<CR>";
          options.desc = "Open Neogit";
        }

        {
          key = "<leader>bb";
          action = "<cmd>Telescope buffers<CR>";
          options.desc = "Show Open Buffers";
        }

        {
          key = "<leader>bd";
          action = "<cmd>Bwipeout<CR>";
          options.desc = "Close Current Buffer";
        }

        {
          key = "<leader>bK";
          action = "<cmd>bufdo :Bwipeout<CR>";
          options.desc = "Close All Buffers";
        }

        {
          key = "<leader>bh";
          action = "<cmd>bprevious<CR>";
          options.desc = "Switch to Previous Buffer";
        }

        {
          key = "<leader>bl";
          action = "<cmd>bnext<CR>";
          options.desc = "Switch to Next Buffer";
        }

        {
          key = "<leader>bk";
          action = "<cmd>b#<CR>";
          options.desc = "Toggle Between Recent Buffers";
        }

        {
          key = "<leader>bj";
          action = "<cmd>b#<CR>";
          options.desc = "Toggle Between Recent Buffers";
        }

        {
          key = "<leader>wh";
          action = "<cmd>wincmd h<CR>";
          options.desc = "Focus Window Left";
        }

        {
          key = "<leader>wj";
          action = "<cmd>wincmd j<CR>";
          options.desc = "Focus Window Down";
        }

        {
          key = "<leader>wk";
          action = "<cmd>wincmd k<CR>";
          options.desc = "Focus Window Up";
        }

        {
          key = "<leader>wl";
          action = "<cmd>wincmd l<CR>";
          options.desc = "Focus Window Right";
        }
      ];
    };
  };
}

