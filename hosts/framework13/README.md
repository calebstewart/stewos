# framework13

Framework Laptop 13 Pro with the Intel Core Ultra Series 3 ("Panther Lake")
mainboard. NixOS only -- no Windows half. Authored 2026-11-11, before the
machine was installed, so the items under "First boot" are real work, not a
checklist to skim.

## Decisions

- **`nixos-hardware.nixosModules.framework-intel-core-ultra-series3`** is the
  hardware profile. Framework's own NixOS doc for this board says exactly that
  and nothing more, and the profile is written by Framework staff. It brings
  fwupd, fprintd, the EC kernel module, `nvme.noacpi=1` and the IIO sensor
  proxy. Do not reach for `framework-amd-ai-300-series`; that is the other
  board sold in this chassis.
- **power-profiles-daemon and thermald, stated explicitly.** nixos-hardware's
  laptop profile turns *TLP* on whenever PPD is off, and NixOS enables PPD
  implicitly only for GNOME and KDE. Without the line a Hyprland host silently
  gets TLP. Framework recommends PPD on every current board, and on Panther
  Lake it measured better performance per watt than tuned-ppd. caelestia's
  power-profile toggle also speaks PPD.
- **Hibernation is on**, as on framework16 and unlike framework-desktop. It
  needs a swap partition at least the size of RAM. The board offers s2idle
  only, which suspend-then-hibernate is fine with.
- **The kernel is `linuxPackages_latest`** from the workstation profile. That
  meets Framework's "7.0+ recommended, latest is best", and 7.0 is where the
  built-in microphone stopped clipping (`limit-mic-boost` quirk). Do not pin
  this host to an LTS kernel.
- **No kernel parameters** beyond the profile's. No community configuration
  for this board needed any. An `xe.enable_psr=1` workaround circulating on
  the forum was later attributed to a badly seated LPCAMM2 module, so it is
  deliberately absent.
- **Display scale 1.6.** The panel is 2880x1920 at 256 PPI. Framework's guides
  say 200% then a 0.8 font scale, which is 160% in effect, and 1.6 divides the
  panel exactly to a 1800x1200 logical desktop. 2 is the integer option but
  leaves 1440x960, cramped at 13.5".
- **Fingerprint reader kept out of USB autosuspend** (udev rule in
  `configuration.nix`). The reader is reported to drop off the bus across a
  resume; this is the standard mitigation and Framework ships a script for the
  same fault on the AMD board's identical sensor. Harmless if the IDs differ.
- **Speaker tuning left off.** nixos-hardware's
  `hardware.framework.laptop13.audioEnhancement` describes itself as tuned for
  the classic chassis and says the Pro needs different tuning. None exists yet.
- **No ollama.** framework16 runs `ollama-rocm`; there is no ROCm on Intel.
  `pkgs.ollama-vulkan` is the equivalent if wanted.
- **`hardware-configuration.nix` is hand-written** in `nixos-generate-config`'s
  shape and matches partitions by label, not UUID. See "First boot".

## First boot

In order. Several of these are the difference between a machine that boots and
one that does not.

1. **Disable Secure Boot in the BIOS for the install** (F2 -> Administer
   Secure Boot -> Enforce Secure Boot -> Disabled). Framework's NixOS guide
   requires it, and the installer does not carry our keys.
2. **Partition with labels**, or replace the hardware file. Either:
   - btrfs root labelled `nixos`, vfat ESP labelled `BOOT`, swap labelled
     `swap` (>= RAM, for hibernation), matching
     `hardware-configuration.nix` as written; or
   - after installing, overwrite `hardware-configuration.nix` with
     `nixos-generate-config --show-hardware-config`.
   Do not mix the two.
3. **Set `system.stateVersion`** in `configuration.nix` to whatever the
   installer generated. It is written as `"26.05"` on the assumption of a
   26.05-era installer. Then never change it.
4. **Secure Boot keys**, before the first `stewctl os switch`: the workstation
   profile enables lanzaboote with `/var/lib/sbctl`, so `sbctl create-keys`,
   then `sbctl enroll-keys --microsoft`, then re-enable Secure Boot in the
   BIOS. Same procedure as the other Framework hosts.
5. **Update the BIOS to 3.04 or later** with `fwupdmgr refresh && fwupdmgr
   update`. The shipping 3.02 clamps the iGPU at an 80 W PL4, and most of the
   open suspend and charger bug reports were filed against it.

## Verify after the first switch

- `hyprctl monitors` -- the EDID description for eDP-1. `home.nix` carries a
  guess (`"CSO MND508ZB1-1"`; the panel is CSOT's MND508ZB1-1). Until the
  string matches, Hyprland's fallback drives the panel at preferred mode and
  automatic scale; nothing else breaks, but 1.6 does not apply.
- `hyprctl devices` -- the built-in keyboard's name. `home.nix` assumes
  `at-translated-set-2-keyboard`, what every Framework 13 so far reports. If
  Caps Lock is still Caps Lock, this is why.
- `lsusb | grep -i 27c6` -- the fingerprint reader's IDs against the udev rule.
- `fprintd-enroll`. A fingerprint satisfies `doas` and polkit on this host and
  nothing else: autologin skips the greeter, and caelestia's locker uses its own
  PAM stack inside the package. Set `services.fprintd.enable = false` to opt out.
- `cat /sys/power/mem_sleep` should read `[s2idle]` alone; `systemctl status
  power-profiles-daemon thermald` both active; `tlp` absent.
- The three keyring checks under "The lock screen says the keyring password is
  invalid" in the repository CLAUDE.md apply here too.

## Known open issues on this board

Tracked in FrameworkComputer/SoftwareFirmwareIssueTracker, none papered over
here. Check these before debugging the configuration.

- **#274** -- system resets instead of resuming from s2idle after longer
  sleeps (BIOS 3.02). Whether 3.04 fixes it is unknown; its release notes were
  not retrievable.
- **#286 / #295** -- after resume the charger stays "online" when unplugged
  (`ucsi_acpi ... failed to re-enable notifications`), so on-battery idle
  policies never fire. `modprobe -r ucsi_acpi && modprobe ucsi_acpi` clears it.
- **#296** -- BE211 Wi-Fi firmware crashes (`NMI_INTERRUPT_UMAC_FATAL`) every
  few minutes on Ubuntu 26.04's 7.0 kernel, taking Bluetooth with it and
  blocking suspend. Distro-specific so far; shows the firmware is still young.
- **#297** -- fingerprint reader unreliable after sleep. Mitigated above; if it
  persists, a `post-resume.target` unit restarting `fprintd` is the next step.
- **#263** (closed) -- the PL4 clamp, fixed by BIOS 3.04.
- Panel power: the PSR2 self-refresh matters a lot; one user measured ~40%
  less idle draw at 60 Hz than 120 Hz. `stewos.desktop.monitors` has no
  refresh-rate field today, so this is not configurable here yet.

## Not done

- The `-vm` apps for `framework16-win` and `gaming-windows` fail
  `nix flake check` (`attribute 'initialRamdisk' missing`). Pre-existing and
  unrelated: `flake.nix` generates a VM app for every `nixosConfigurations`
  entry and the NixOS-WSL distros have no initrd. `framework13-vm` is fine.
- No `hosts/common` refactor: `home.nix` is a near copy of framework16's, by
  the repository's convention of one `home.nix` per host.
