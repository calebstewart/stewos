{
  nixos-single = {
    description = "StewOS flake with a single system and user";
    path = ./nixos-single/src;
    welcomeText = builtins.readFile ./nixos-single/README.md;
  };
}
