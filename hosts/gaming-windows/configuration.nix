# Windows 11 desktop: the *system* configuration -- the machine, applied
# elevated -- and the NixOS-WSL distro on it that evaluates and applies both
# halves. The user's half is home.nix. See mkWindowsHost in flake.nix.
{ ... }:
{
  imports = [ ../common/windows/configuration.nix ];

  # Two things this machine used to be, and is not any more. It began life as a
  # Looking Glass guest -- the Looking Glass host, QEMU-GA and the SPICE guest
  # tools (with their BalloonService and vdservice) were all still installed and
  # set to start -- and it ran on a ROG Strix mainboard, which brought the whole
  # ASUS stack: Armoury Crate, Armoury Crate Service, ASUS Framework Service,
  # ROG Live Service, AsusCertService, the ASUS update services and five tasks
  # under \ASUS\. It is a Framework AMD mainboard on bare metal now, and all of
  # that was uninstalled by hand on 2026-09-17. By hand because winpkgs prunes
  # only what it owns and owned none of it; nothing below would have removed
  # them. Microsoft Teams, Teams (personal) and OneDrive went the same way, the
  # last taking its three scheduled tasks with it.

  # Machine-wide installs. Everything here offers only a machine-scope
  # installer, which a home configuration cannot take because it never
  # elevates: winget answers a user-scope install of one of these with "no
  # applicable installer". The per-user half of the machine is in home.nix.
  winget.packages = [
    # Daily use. Chrome is installed and wanted and still not listed: winget
    # does not recognise the copy that is here (it correlates the ARP entry to
    # Google.Chrome.Beta.EXE, so `Google.Chrome` reads as absent and every
    # apply would try to install it), and the Google.Chrome manifest currently
    # fails its own hash check, because Google republishes that URL in place.
    # Both ends of that have to be right before it can be declared.
    "Valve.Steam"
    "Mozilla.Firefox"
    "Microsoft.WSL" # also what winpkgs itself runs in

    # This desk's hardware. AMD Software and the chipset drivers come from
    # AMD's own installer rather than winget, so they cannot be said here; the
    # AMD half of the answer is the noise-suppression Run entry in home.nix.
    "SteelSeries.GG"
    "Logitech.OptionsPlus"

    # Toolchains. Both of these are multi-gigabyte, and a fresh apply fetches
    # them unattended.
    "Microsoft.VisualStudio.2022.BuildTools"
    "Microsoft.WindowsSDK.10.0.26100"
  ];

  windows = {
    startup = {
      # SteelSeries GG has to be running for the headset and mouse to keep
      # their settings, so its entry is wanted. SecurityHealth (Defender's
      # tray icon) and RtkAudUService (Realtek's audio helper) are here too
      # and deliberately undeclared: Windows and the driver own them, and a
      # fresh install grows them again by itself.
      SteelSeriesGG = ''"C:\Program Files\SteelSeries\GG\SteelSeriesGGEZ.exe" -dataPath="C:\ProgramData\SteelSeries\GG" -dbEnv=production -auto=true'';

      # Logitech's installer nagware, a separate package from Options+ above,
      # which does not need it.
      "Logi Download Assistant" = null;
    };

    # Only services whose start mode this host means to change. A vendor
    # service left as its installer set it -- OptionsPlusUpdaterService,
    # SteelSeries' update proxy -- is deliberately *not* listed: winpkgs
    # rewrites a declared service's path and display name on every apply, and
    # creates it outright on a machine that does not have it yet, which on a
    # fresh install would mean a service pointing at a program that is not
    # there.
    services.AUEPLauncher = {
      # The other half of the AMD User Experience Program: its Run entry is
      # already `StartAUEP = null` in ../common/windows/configuration.nix, but
      # the uploader service was Auto and running, and AMD ships no
      # uninstaller for it. Disabling writes the start mode only -- winpkgs
      # does not stop a running service for this -- so it goes quiet at the
      # next boot.
      displayName = "AMD User Experience Program Data Uploader";
      command = ''"C:\Program Files\AMD\CIM\..\Performance Profile Client\AUEPDU.exe"'';
      startType = "disabled";
    };

    # Tasks to turn off, and only those. `false` for a task this machine does
    # not have counts as satisfied, so these are safe on a fresh install;
    # `true` is not, because enabling a task that is not there is an error.
    # That is why AMD's own -- AMDRyzenMasterSDKTask, StartCN, StartCNBM and
    # StartDVR, which AMD Software installs and which belong on AMD hardware
    # -- are wanted here and still declared nowhere.
    scheduledTasks = {
      # Chrome's "platform experience helper": telemetry, daily, on a metrics
      # schedule and at every unlock. Chrome itself stays.
      "\\GoogleUserPEH\\RunPlatformExperienceHelper_Daily" = false;
      "\\GoogleUserPEH\\RunPlatformExperienceHelper_Metrics" = false;
      "\\GoogleUserPEH\\RunPlatformExperienceHelperOnUnlock" = false;

      # Firefox stays, but it updates itself when it starts and needs neither a
      # background updater nor an agent watching which browser is default. The
      # first name embeds this user's SID, so it matches on this machine and
      # silently says nothing anywhere else.
      "\\Mozilla\\Firefox Background Update S-1-5-21-2181932373-2550833737-810432524-1001 308046B0AF4A39CB" =
        false;
      "\\Mozilla\\Firefox Default Browser Agent 308046B0AF4A39CB" = false;
    };
  };

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
