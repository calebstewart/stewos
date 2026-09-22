# Plan: fix the fractional-scale text-ellipsis bug upstream

A ready-to-execute plan for a future agent to implement the real fix in
`hyprwm/hyprtoolkit` (and optionally upstream our interim agent patch to
`hyprwm/hyprpolkitagent`). Read `upstream-issue.md` in this directory first — it
contains the full diagnosis and trace evidence; this file assumes it.

## Context recap (one paragraph)

`CTextElement` captures its available room in `lastMaxSize` during `reposition()`.
For unclamped text in auto-sized layouts, that hint equals the text's own preferred
size measured at the startup scale (1.0). When `wp_fractional_scale_v1` delivers a
non-integer scale, fonts re-render at `std::round(size * scale)` physical pixels — a
slightly different *logical* size — and pango's per-size hinting shifts extents
further. The re-measured text exceeds the stale hint, `prepPangoLayout` clamps and
END-ellipsizes, and nothing invalidates the hint or re-grows the auto-sized ancestor.
Result: permanent ellipsis. Locally we carry `clamp-header.patch` (this directory) on
hyprpolkitagent as a band-aid.

## Repos and key files

- `github:hyprwm/hyprtoolkit` (the real fix)
  - `src/element/text/Text.cpp` — `CTextElement::reposition()` (hint capture, the
    flip-flop guard comment), `STextImpl::prepPangoLayout()` (rounded font size,
    clamp + `PANGO_ELLIPSIZE_END`), `STextImpl::renderTex()` (same rounding),
    `paint()` (per-element scale-change re-measure).
  - `src/window/IWaylandWindow.cpp` / `WaylandWindow.cpp` — fractional-scale event
    handler (`setPreferredScale`), and `configure()` which shows how a full-root
    relayout is done (`m_rootElement->reposition({0,0,logicalSize})`).
  - `src/layout/Positioner.cpp`, `src/element/rowLayout/`, `columnLayout/`,
    `src/element/LinearLayout.hpp` — how auto-sized layouts derive children's boxes
    and the `maxSize` room hint.
  - `src/helpers/Env.cpp` — `HT_TRACE=1` enables the text traces used to verify.
- `github:hyprwm/hyprpolkitagent` (optional interim PR)
  - `src/ui/Dialog.cpp` — apply `clamp-header.patch` from this directory verbatim
    (one added `->clampSize({(double)cfg.passwordFieldWidth, -1.0})` on the header).

## Implementation plan (toolkit)

Two changes, independent but complementary; do both.

### 1. Scale-invariant text measurement

In `STextImpl::prepPangoLayout()` and `renderTex()`:

- Replace `std::round(lastFontSizeUnscaled * lastScale)` with the unrounded product,
  passed to pango as fractional size: `pango_font_description_set_size(desc,
  lround(lastFontSizeUnscaled * lastScale * PANGO_SCALE))` — pango sizes are in
  `PANGO_SCALE` units precisely so fractional pixel/point sizes work.
- For the *measurement* layout, disable metrics hinting so extents scale linearly:
  create `cairo_font_options_t`, `cairo_font_options_set_hint_metrics(opts,
  CAIRO_HINT_METRICS_OFF)`, apply via `pango_cairo_context_set_font_options` on the
  layout's context. (Rendering can keep its current options; only measurement
  consistency matters for layout.)
- Expected effect: `getTextSizePreferred()` returns the same logical size at every
  scale, so a box measured at scale 1.0 still fits the scale-1.5 re-render. This
  alone fixes the observed bug for any text whose ancestors sized to the scale-1.0
  preferred.

### 2. Invalidate stale hints on scale change

In the window's fractional-scale handler (`WaylandWindow.cpp`,
`setPreferredScale`), when the scale actually changes:

- Walk the element tree (`m_rootElement->impl->breadthfirst(...)`, see
  `ToolkitWindow.cpp` for an existing walk) and give elements a chance to drop
  scale-derived caches. Cleanest shape: add a virtual `IElement::onScaleChanged()`
  (default no-op); `CTextElement` implements it by resetting
  `m_impl->lastMaxSize = {-1, -1}`, updating `lastScale`, re-measuring
  `preferred`, and marking `needsTexRefresh`.
- Then trigger a full relayout from the root exactly as `configure()` does, so
  auto-sized ancestors re-query `preferredSize()` *after* the re-measures, rather
  than each text only rescheduling its own subtree.
- Watch out for the flip-flop scenario the existing comment in
  `CTextElement::reposition()` guards against (auto-sized label whose box equals its
  own clamped preferred feeding back): after the root relayout, hints re-captured
  from parents must reflect the *new* preferred sizes; with change 1 in place the
  sizes are scale-stable, so the loop converges immediately.

## Verification

Environment: any compositor with fractional scaling; the original repro used
Hyprland with a 3840x2160 monitor at scale 1.5. Build with the flake
(`nix build .#default` in each repo; both flakes follow standard hyprwm layout).

1. Unit-style: `HT_TRACE=1` + a minimal hyprtoolkit app (or hyprpolkitagent with its
   header clamp *removed*) on a scale-1.5 output. Before: header renders with
   `maxSize` set and `ellipsize: true`, tex narrower than the full string. After:
   either no maxSize clamp or a clamp ≥ desired; rendered text complete.
2. Visual matrix: scales 1.0, 1.25, 1.5, 2.0 — header complete at all of them; no
   layout jumps when the scale event arrives after first paint.
3. Regression: dynamic text (`setText` on a status label in an auto-sized row) still
   settles without oscillating (the flip-flop case); clamped texts still wrap/ellipsize
   per their explicit `clampSize` semantics.
4. hyprpolkitagent smoke test: prompt via `run0 true`. Gotchas learned debugging
   this: polkit allows a single registered agent per session — stop any running
   agent service first (`systemctl --user stop hyprpolkitagent`) or registration
   fails silently for the new one and a *stale* agent renders the dialog; the agent
   resolves `~/.config` via the real home, not `$XDG_CONFIG_HOME`/`$HOME` overrides.

## Cleanup once merged

- Drop `clamp-header.patch` and the `overrideAttrs` in `pkgs/hyprpolkitagent/`
  (keep the package as a plain passthrough or remove it and consume the input
  directly again), and delete these two markdown files.
- The related-but-separate hyprpolkitagent issues (configured `window_width` never
  honored — window always opens at its 460 minimum; fixed 440px default height
  instead of content-sized window; command string pre-truncated to 55 chars at build
  time) are not covered by this plan and remain open candidates for follow-up
  upstream reports.
