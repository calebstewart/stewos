{ ... }:
{
  description = "StewOS flake with a single system and user";
  path = ./src;
  welcomeText = builtins.readFile ./README.md;
}
