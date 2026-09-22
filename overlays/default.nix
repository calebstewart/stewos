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

      # The upstream caelestia-shell package, which pkgs/caelestia-shell patches
      # to unlock the login keyring from the lock screen. "with-cli" rather than
      # "default" because programs.caelestia.cli.enable is set and upstream's
      # home-manager module defaults to the with-cli variant, so overriding
      # "default" would quietly drop the bundled CLI. Linux-only upstream, hence
      # the "or null".
      caelestia-shell-upstream =
        inputs.caelestia-shell.packages.${prev.stdenv.hostPlatform.system}.with-cli or null;

      # The upstream hyprpolkitagent package, which pkgs/hyprpolkitagent
      # patches. The flake only has Linux systems, hence the "or null".
      hyprpolkitagent-upstream =
        inputs.hyprpolkitagent.packages.${prev.stdenv.hostPlatform.system}.default or null;

      # The upstream hyprqt6engine package, which pkgs/hyprqt6engine rebuilds
      # against the Qt stdenv so its plugin can actually be loaded. Linux-only
      # upstream, hence the "or null".
      hyprqt6engine-upstream =
        inputs.hyprqt6engine.packages.${prev.stdenv.hostPlatform.system}.default or null;

      # The RASI DSL used to generate Rofi themes and configs.
      inherit (import ../lib { inherit (prev) lib; }) rasi;
    }
  );
}
