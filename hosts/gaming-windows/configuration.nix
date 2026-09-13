# Windows 11 desktop: the *system* configuration -- the machine, applied
# elevated -- and the NixOS-WSL distro on it that evaluates and applies both
# halves. The user's half is home.nix. See mkWindowsHost in flake.nix.
{ ... }:
{
  imports = [ ../common/windows/configuration.nix ];

  # A desktop: stay up, and let the power button mean off.
  power = {
    sleep.computer = "never";
    sleep.display = 30;
    sleep.harddisk = "never";
    buttons.power = "shutdown";
    hibernation = false;
  };

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
