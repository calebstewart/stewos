# Windows 11 desktop, and the NixOS-WSL distro on it that evaluates and applies
# this configuration. See mkWindowsHost in flake.nix.
{ ... }:
{
  # Bare minimum to prove the pipeline: both are already installed, so the first
  # plan should report everything unchanged.
  winpkgs.packages.winget = [
    "Git.Git"
    "Microsoft.PowerShell"
  ];

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  winpkgs.wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
