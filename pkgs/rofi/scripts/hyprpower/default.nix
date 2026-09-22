{
  lib,
  jq,
  hyprland,
  systemd,
  writeShellApplication,
}:
writeShellApplication {
  name = "hyprpower";
  runtimeInputs = [
    jq
    hyprland
    systemd
  ];
  text = builtins.readFile ./hyprpower.sh;

  meta = {
    description = "Rofi script mode for Hyprland session power actions";
    # Depends on Hyprland and systemd.
    platforms = lib.platforms.linux;
  };
}
