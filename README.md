# StewOS - NixOS and Nix-Darwin Configurations
This repository houses my personal NixOS, Nix-Darwin and Home-Manager configurations for all my systems.
It also houses some utility library functions, and a few custom packages which are used for my system
configurations.

Generally, the system is configured with fields under `stewos.*`. The majority of configuration comes
from `stewos.desktop` which will configure Hyprland and my custom [stew-shell] shell UI and associated
services (`hyprlock`, `swaync`, etc.) for NixOS. For Nix-Darwin, `stewos.desktop` configures Aerospace
and associated services for customizing the graphical interface in MacOS.

## Defining a System
To define a system, create a new directory under [systems/] and a `default.nix` in that directory.
`default.nix` is a function taking all inputs from the flake, and should return the flake outputs.
Additionally, `default.nix` takes a `hostname` input which is the name of the directory containing
the file. This just decreases constant duplication because the name of the directory is often the
hostname of the system (or maybe the name of the user for Home-Manager-only systems). The outputs
from all systems are merged to create the outputs of the flake.

There are shortcut functions defined in `stewos.lib` to create NixOS, Nix-Darwin or Home-Manager
configurations which automatically include the StewOS NixOS, Nix-Darwin and/or Home-Manager modules.

```nix
# Creating a NixOS configuration=
nixosConfigurations.${hostname} = stewos.lib.mkNixOSSystem {
  inherit hostname;

  system = "x86_64-linux";
  modules = [./hardware-configuration.nix ./configuration.nix];
}

# Creating a Nix-Darwin Configuration
darwinConfigurations.${hostname} = stewos.lib.mkNixDarwinSystem {
  inherit hostname;

  system = "aarch64-darwin";
  modules = [./configuration.nix];
};
```

You can also use `stewos.lib.mkNixOSVirtualMachineApp` to create a Nix Flakes app output which will
build and execute a virtual machine of the given NixOS configuration.

```nix
apps.${system}.${hostname} = stewos.lib.mkNixOSVirtualMachineApp hostname nixosConfigurations.${hostname}
```

## Terminal Configuration
The terminal for both NixOS and Nix-Darwin is Alacritty. The color scheme for Alacritty is defined by
the root `colorScheme` configuration. For the existing systems, I generally use `catpuccin-mocha`.
The default shell is `zsh` for all systems.

<img width="2131" height="1123" alt="image" src="https://github.com/user-attachments/assets/3d9ffb51-4ef8-4122-8a9c-522773afaa6b" />

## Neovim Configuration
If you enable `stewos.neovim.enable`, then StewOS will configure Neovim using [nixvim]. There are a lot
of moving parts in vim configurations, so I won't go into all the details, but the improtant big pieces
are:

1. Configured to use the color scheme defined in the root `colorScheme` config.
2. Use ` ` (SPACE) as the global leader, which behaves similarly to emacs.
3. Enable support for `wl-copy` under NixOS (ignored for Nix-Darwin).
4. Enable plugins: `nix`, `lualine`, `lsp-format`, `oil`, `cmp-nvim-lsp-signature-help`, `transparent`, `noice`, `neogit`, `vim-bbye`, `illuminate`, `web-devicons`, `treesitter`, `markdown-preview`, `trouble`, `notify`, `toggleterm`, `lspsaga`, `lsp`, `cmp`, `none-ls`, `telescope`, `neotree`, `which-key`.
5. LSP Servers: `lua_ls`, `gopls`, `nixd`, `pyright`, `clangd`, `jdtls`, `ts_ls`, `vala_ls`, `mesonlsp`, `ruby_lsp`, `rust_analyzer`, `gh_actions_ls`.
6. A bunch of keymaps with helpful documentation.

<img width="3826" height="2104" alt="image" src="https://github.com/user-attachments/assets/2651791c-c14e-4a41-87fd-9f40a92eaa9e" />

[systems/]: ./systems
[stew-shell]: https://github.com/calebstewart/stew-shell
[nixvim]: https://github.com/nix-community/nixvim
