# The StewOS overlay: adds a "stewos" package scope to nixpkgs.
#
# This is the single boundary where flake inputs meet packages. Everything under
# pkgs/ is a plain callPackage derivation; the values below are the only ones
# that come from a flake input, and they are injected as scope members so that
# callPackage resolves them by argument name.
#
# Exported as flake.overlays.default, so any other flake can do:
#   nixpkgs.overlays = [ stewos.overlays.default ];
#   ... then use pkgs.stewos.wl-gen-uuid
inputs: final: prev: {
  stewos = prev.lib.makeScope prev.newScope (
    self:
    (import ../pkgs self)
    // {
      # Palette used by the default Rofi theme.
      colorScheme = inputs.nix-colors.colorSchemes.catppuccin-mocha;

      # Source tree for gh-actions-language-server, which is a "flake = false"
      # input rather than something fetched inside the derivation.
      gh-actions-language-server-src = inputs.gh-actions-language-server;

      # The RASI DSL used to generate Rofi themes and configs.
      inherit (import ../lib { inherit (prev) lib; }) rasi;
    }
  );
}
