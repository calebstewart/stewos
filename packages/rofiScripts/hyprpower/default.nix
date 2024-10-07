{
  jq,
  hyprland,
  systemd,
  mkRofiScript
}: mkRofiScript {
  name = "hyprpower";
  runtimeInputs = [jq hyprland systemd];
  text = builtins.readFile ./hyprpower.sh;
}
