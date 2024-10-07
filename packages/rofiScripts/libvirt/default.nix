{
  libvirt,
  coreutils,
  libnotify,
  virt-viewer,
  gnugrep,
  mkRofiScript,
}: mkRofiScript {
  name = "libvirt";

  runtimeInputs = [
    libvirt
    coreutils
    libnotify
    virt-viewer
    gnugrep
  ];

  text = builtins.readFile ./libvirt.sh;
}
