{
  lib,
  libvirt,
  coreutils,
  libnotify,
  virt-viewer,
  gnugrep,
  writeShellApplication,
}:
writeShellApplication {
  name = "libvirt";

  runtimeInputs = [
    libvirt
    coreutils
    libnotify
    virt-viewer
    gnugrep
  ];

  text = builtins.readFile ./libvirt.sh;

  meta = {
    description = "Rofi script mode for starting and connecting to libvirt VMs";
    platforms = lib.platforms.linux;
  };
}
