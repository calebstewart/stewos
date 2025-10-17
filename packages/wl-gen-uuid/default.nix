{
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
}
