# Windows 11 desktop: the *system* configuration -- the machine, applied
# elevated -- and the NixOS-WSL distro on it that evaluates and applies both
# halves. The user's half is home.nix. See mkWindowsHost in flake.nix.
{ ... }:
{
  # Windows system settings
  windows = {
    developer.developerMode = true;
    userChoiceProtection.enable = false;

    # Machine-wide policy; the per-user privacy settings are in home.nix.
    privacy = {
      activityFeed = false;
      telemetry = "required";
    };

    startup = {
      # AMD User Experience Program
      StartAUEP = null;
    };

    keyboard.lockShortcut = false;
  };

  # steward in C:\Program Files\steward, registered as a per-user service:
  # every sign-in starts a manager that runs the units home.nix declares.
  services.steward.enable = true;

  power = {
    plan = "balanced";
    sleep.computer = "never";
    sleep.display =  30;
    sleep.harddisk = "never";
    buttons.power = "shutdown";
    hibernation = false;
    fastStartup = false;
  };

  time = {
    timeZone = "America/Chicago";
    hardwareClockInLocalTime = false;
    autoTimeZone = false;

    ntp = {
      enable = true;
      servers = ["time.cloudflare.com" "time.nist.gov"];
      pollInterval = 3600;
      maxCorrection = "unlimited";
    };
  };

  security.sudo = {
    enable = true;
    mode = "normal";
  };

  # The distro is winpkgs' slim base (NixOS-WSL, flakes, git) plus whatever goes
  # here. Only the state version so far.
  wsl.modules = [
    { system.stateVersion = "26.05"; }
  ];
}
