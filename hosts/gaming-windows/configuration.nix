# Windows 11 desktop: the *system* configuration -- the machine, applied
# elevated -- and the NixOS-WSL distro on it that evaluates and applies both
# halves. The user's half is home.nix. See mkWindowsHost in flake.nix.
{ pkgs, ... }:
{
  winpkgs.developer.developerMode = true;

  # Machine-wide tools: packages whose winget installer is machine-scope only,
  # which a home configuration cannot take. LLVM is the C compiler Neovim's
  # treesitter needs (stewos.neovim in home.nix); its installer leaves PATH
  # alone, so the machine PATH gets its bin directory here.
  environment.systemPackages = [ (pkgs.winpkgs.fromWinget "LLVM.LLVM") ];
  winpkgs.environment.path = [ ''C:\Program Files\LLVM\bin'' ];

  # Machine-wide policy; the per-user privacy settings are in home.nix.
  winpkgs.privacy = {
    activityFeed = false;
    telemetry = "required";
  };

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  winpkgs.wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
