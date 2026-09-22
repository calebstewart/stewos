{
  lib,
  libuuid,
  wl-clipboard,
  writeShellApplication,
}:
writeShellApplication {
  name = "wl-gen-uuid";
  runtimeInputs = [
    libuuid
    wl-clipboard
  ];
  text = "uuidgen | wl-copy";

  meta = {
    description = "Generate a UUID and put it on the Wayland clipboard";
    # wl-clipboard is Wayland-only.
    platforms = lib.platforms.linux;
  };
}
