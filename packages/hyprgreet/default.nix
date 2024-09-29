{pkgs, ...}: pkgs.writeShellApplication {
  name = "hyprgreet";

  runtimeInputs = with pkgs; [
    hyprland
    hyprlock
    jq
  ];

  text = ''
    
  '';
}
