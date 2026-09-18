# Policy shared by the Windows machines' *system* configurations -- HKLM,
# %ProgramData%, the clock -- the way ../workstation.nix is for the NixOS ones.
# The user's half is ./home.nix.
#
# Anything genuinely per-machine stays in that machine's configuration.nix:
# power (a desktop never sleeps, a laptop must), keyboard remaps, and the WSL
# distro's stateVersion, which must never move in here for the same reason
# system.stateVersion never moves into shared NixOS configuration.
{ config, ... }:
{
  windows = {
    developer.developerMode = true;
    userChoiceProtection.enable = false;

    # Machine-wide policy; the per-user privacy settings are in ./home.nix.
    privacy = {
      activityFeed = false;
      telemetry = "required";
    };

    startup = {
      # AMD User Experience Program
      StartAUEP = null;
    };

    keyboard.lockShortcut = false;

    # Hyper-V, driven from the user's ordinary session. A member of the
    # built-in Hyper-V Administrators group has full control of VMMS without
    # elevating, and UAC's filtered token keeps that group, so an
    # administrator's unelevated shell -- and every steward unit started from
    # their logon -- has it. The members are this machine's home users, read
    # off winpkgs.homes so the name is written once, in flake.nix. Membership
    # reaches the logon token at the next sign-in and the feature wants a
    # restart the first time; winpkgs reports both and does neither. WSL's
    # Virtual Machine Platform is a separate feature, implied by `wsl`.
    features.Microsoft-Hyper-V-All = true;
    localGroups."Hyper-V Administrators".members = map (h: h.config.home.username) config.winpkgs.homes;
  };

  # Fast startup shuts down by hibernating the kernel session, which leaves
  # the disks and firmware in a state another OS cannot trust -- on a dual
  # boot it is the one to have off. Whether real hibernation is available is
  # per-host, as it is on NixOS.
  power = {
    plan = "balanced";
    fastStartup = false;
  };

  time = {
    timeZone = "America/Chicago";

    # The hardware clock is UTC, which is what NixOS assumes. Only matters to
    # a machine that also boots Linux, but costs nothing on one that does not.
    hardwareClockInLocalTime = false;
    autoTimeZone = false;

    ntp = {
      enable = true;
      servers = [
        "time.cloudflare.com"
        "time.nist.gov"
      ];
      pollInterval = 3600;
      maxCorrection = "unlimited";
    };
  };

  # security.sudo = {
  #   enable = true;
  #   mode = "normal";
  # };

  security.gsudo = {
    enable = true;
    cacheMode = "auto";
    enforceUacIsolation = false;
  };
}
