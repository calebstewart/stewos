# Every StewOS nix-darwin module, plus the macOS system defaults.
{ inputs, ... }:
{
  imports = [
    inputs.home-manager.darwinModules.default
    inputs.nur.modules.darwin.default
    inputs.stylix.darwinModules.stylix

    ./nh.nix
  ];

  # Setup Nix configuration
  nix = {
    optimise.automatic = true;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # Setup Nix Helper for easy building
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  # Enable mandb and nix documentation
  documentation = {
    enable = true;
    man.enable = true;
  };
}
