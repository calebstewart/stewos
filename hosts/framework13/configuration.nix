# Framework Laptop 13 Pro, Intel Core Ultra Series 3 ("Panther Lake") mainboard.
#
# Framework's own Linux docs for this board come down to "import the
# nixos-hardware profile and run a recent kernel" (linux-docs/framework13/
# FW-13-Pro-NixOS-all-Intel-Core-Ultra-Series-3.md), and that profile is written
# by Framework staff. It handles fwupd, fprintd, the EC kernel module, the
# `nvme.noacpi=1` power tweak and the IIO sensor proxy. What is left here is the
# policy the profile leaves to the host.
{
  inputs,
  ...
}:
{
  imports = [
    ../common/workstation.nix
    inputs.nixos-hardware.nixosModules.framework-intel-core-ultra-series3
  ];

  # The NixOS release this machine was first installed from. Per-machine on
  # purpose: it must not follow whatever the shared modules were written for.
  # Set it to whatever the installer's generated configuration.nix says the
  # first time, then DO NOT CHANGE.
  system.stateVersion = "26.05";

  # The kernel is the workstation profile's linuxPackages_latest, which is what
  # Framework asks for on this board (minimum 6.19, recommended 7.0+, "best
  # experience: latest"). 7.0 is also where the internal microphone stopped
  # clipping: the kernel used to pick the highest mic boost, and Framework's
  # `limit-mic-boost` quirk landed there. Do not pin this host to an LTS kernel.

  # This is a laptop, so S4 is worth having, as on framework16. It only works if
  # the swap partition can hold the hibernation image, so size swap at least as
  # large as RAM (see hardware-configuration.nix). The board offers s2idle only
  # -- /sys/power/mem_sleep has no "deep" -- which suspend-then-hibernate is
  # fine with. Nothing here relaxes security.protectKernelImage; it already
  # defaults to false, so `nohibernate` is not on the command line.
  systemd.sleep.settings.Sleep = {
    AllowHibernation = true;
    AllowSuspendThenHibernate = true;
    AllowHybridSleep = true;
  };

  # Power management is power-profiles-daemon, stated explicitly because it is
  # not what we would get by default: nixos-hardware's laptop profile turns TLP
  # on whenever PPD is off, and NixOS only enables PPD implicitly for GNOME and
  # KDE, not for a Hyprland session. Framework's guidance is PPD on every
  # current board, and on Panther Lake specifically PPD leaves intel_pstate on
  # powersave with EPP "performance", which measured better performance per
  # watt than tuned-ppd's performance governor. caelestia's power-profile
  # toggle also talks to PPD. thermald keeps the CPU inside the DPTF envelope,
  # which is what Framework's Ubuntu images run alongside it.
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;

  # The fingerprint reader (Goodix MOC, in the power button) is fprintd's, which
  # the hardware profile enables; libfprint's goodixmoc driver knows this part.
  # With autologin there is no greeter password, and the lock screen is
  # caelestia's own PAM stack inside the package (see pkgs/caelestia-shell), so
  # on this host a fingerprint only ever satisfies doas and polkit. Enrol with
  # `fprintd-enroll`.
  #
  # The reader is reported to drop off USB across a resume ("Cannot run while
  # suspended"), the same fault Framework's Fingerprint-Wake-Workaround exists
  # for on the AMD board's identical sensor. Keeping it out of USB autosuspend
  # is the usual mitigation. The IDs are from Framework's issue tracker; check
  # them against `lsusb` and this rule is a no-op if they differ.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="609c", ATTR{power/control}="on"
  '';

  # nixos-hardware's speaker tuning (hardware.framework.laptop13.audioEnhancement)
  # stays off: its own description says it is tuned for the classic chassis and
  # that the Pro needs different tuning, which nobody has published yet.

  # Default to Eastern
  time.timeZone = "America/New_York";
}
