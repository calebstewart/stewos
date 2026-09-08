# Windows 11 desktop: the *system* configuration -- the machine, applied
# elevated -- and the NixOS-WSL distro on it that evaluates and applies both
# halves. The user's half is home.nix. See mkWindowsHost in flake.nix.
{ ... }:
{
  windows.developer.developerMode = true;

  # Machine-wide policy; the per-user privacy settings are in home.nix.
  windows.privacy = {
    activityFeed = false;
    telemetry = "required";
  };

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
