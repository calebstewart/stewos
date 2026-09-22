# The upstream hyprpolkitagent (from the flake input, injected into the scope
# by overlays/default.nix) with a local fix on top.
#
# The patch clamps the "Authentication Required" header like the dialog's
# other texts. Without it, hyprtoolkit hands unclamped auto-sized text a room
# hint equal to its own scale-1.0 preferred size and never re-grows it after
# a fractional-scale change re-measures the font, so the header permanently
# END-ellipsizes on scaled monitors. Drop the patch when fixed upstream.
#
# The upstream package only exists for Linux systems, so the injected value
# is null elsewhere; flake.nix's packages filter drops the null.
{ hyprpolkitagent-upstream }:
if hyprpolkitagent-upstream == null then
  null
else
  hyprpolkitagent-upstream.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./clamp-header.patch ];
  })
