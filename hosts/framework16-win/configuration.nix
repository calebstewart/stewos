# Framework 16, Windows side of the dual boot: the *system* configuration --
# the machine, applied elevated -- and the NixOS-WSL distro on it. The user's
# half is home.nix; see mkWindowsHost in flake.nix.
#
# The same laptop as ../framework16, not a copy of it: NixOS is on the 4 TB
# NVMe with its own ESP, Windows on the 2 TB one with another, and the firmware
# boot menu picks between them. Nothing here touches the Linux disk.
{ ... }:
{
  imports = [ ../common/windows/configuration.nix ];

  # A laptop: sleep on the lid and when idle, and hibernate after a couple of
  # hours asleep on battery -- the NixOS side opts into S4 for the same
  # reason. Safe on this dual boot because the two systems share no disk:
  # hibernated Windows leaves nothing NixOS would mount. Fast startup stays
  # off (shared policy), which is the part that would not be.
  power = {
    sleep = {
      computer = {
        ac = 30;
        battery = 15;
      };
      display = {
        ac = 10;
        battery = 5;
      };
      hibernate = {
        ac = "never";
        battery = 120;
      };
    };
    buttons = {
      lidClose = "sleep";
      power = "sleep";
    };
    hibernation = true;
  };

  # Caps Lock is Escape, as on the NixOS side. There it is set for the built-in
  # keyboard only; Windows' scancode map is machine-wide, so an external
  # keyboard gets it too. Read by the keyboard driver at boot.
  windows.keyboard.remap.CapsLock = "Escape";

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. It was first set up at 26.05. DO NOT CHANGE.
  wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
