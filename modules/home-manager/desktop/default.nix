# Graphical desktop.
#
# ./options.nix declares the whole settings surface and says nothing about how
# it is delivered; ./linux and ./darwin each implement that surface for their
# platform. This file holds only what is genuinely common to both, plus the
# checks that a binding is well formed before either backend tries to render
# it.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.desktop;
  vocabulary = import ./vocabulary.nix;

  # Bindings the user asked for, paired with the name they gave them so an
  # assertion can point at the right one.
  named = lib.mapAttrsToList (name: binding: { inherit name binding; }) cfg.bindings;
  active = lib.filter ({ binding, ... }: binding.enable) named;

  # Why a binding is malformed, or null if it is fine. Checked here rather than
  # in the type so the message can name the binding.
  malformed =
    { name, binding }:
    if binding.action == null && binding.command == null then
      ''set neither "action" nor "command"''
    else if binding.action != null && binding.command != null then
      ''set both "action" and "command"; set exactly one''
    else if lib.elem binding.action vocabulary.directionalActions && binding.direction == null then
      ''use action "${binding.action}", which needs a "direction"''
    else if lib.elem binding.action vocabulary.workspaceActions && binding.workspace == null then
      ''use action "${binding.action}", which needs a "workspace"''
    else
      null;

  badBindings = lib.filter ({ reason, ... }: reason != null) (
    map (entry: {
      inherit (entry) name;
      reason = malformed entry;
    }) active
  );
in
{
  imports = [
    ./options.nix

    ./linux
    ./darwin
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = badBindings == [ ];
        message = ''
          These stewos.desktop.bindings are malformed:
          ${lib.concatMapStringsSep "\n" (b: "  ${b.name}: ${b.reason}") badBindings}
        '';
      }
    ];

    home.packages = [
      cfg.fonts.ui.package
      cfg.fonts.monospace.package
      pkgs.openmoji-color
      pkgs.nerd-fonts.jetbrains-mono
    ];

    fonts.fontconfig = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      defaultFonts.emoji = [ "OpenMoji Color" ];
    };

    home.file."Pictures/Wallpapers/wallpaper.jpg".source = cfg.wallpaper;
  };
}
