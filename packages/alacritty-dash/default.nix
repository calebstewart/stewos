{
  jq,
  hyprland,
  alacritty,
  writeShellApplication,

  windowClass ? "dash",
  command ? ''alacritty --class "$TOGGLE_WINDOW_CLASS"'',
  specialWorkspace ? "dash",
  runtimeInputs ? [alacritty],
}: writeShellApplication {
  name = "${specialWorkspace}DashToggle";
  runtimeInputs = [jq hyprland] ++ runtimeInputs;

  # Environment variables
  TOGGLE_WINDOW_CLASS = windowClass;
  TOGGLE_SPECIAL_WORKSPACE = specialWorkspace;

  text = ''
    existing=$(hyprctl clients -j | jq -r '.[] | select(.class == "$TOGGLE_WINDOW_CLASS") | .address' && true)
    if [ -z "$existing" ]; then
      exec ${command}
    else
      hyprctl dispatch togglespecialworkspace "$TOGGLE_SPECIAL_WORKSPACE"
    fi
  '';
}
