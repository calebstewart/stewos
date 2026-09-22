# Unclamped auto-sized text permanently ellipsizes after a fractional-scale change

**Repo this issue is for:** `hyprwm/hyprtoolkit` (observed through `hyprwm/hyprpolkitagent`, which is a 100% reproduction)

## Summary

On a fractional-scale output, a `CTextElement` without an explicit `clampSize`, placed
in an auto-sized layout, permanently renders END-ellipsized even when its window has
abundant free space. The text's available-room hint (`lastMaxSize`) is captured at
scale 1.0 as exactly its own preferred size, and after the `wp_fractional_scale_v1`
event re-measures the font at the new (rounded) pixel size, the re-measured text no
longer fits its stale hint — and nothing ever re-grows the hint or the auto-sized
ancestor that produced it.

The most visible casualty: hyprpolkitagent's "Authentication Required" header shows as
"Authentication Requir…" on every prompt, at any window size, on scaled monitors.

## Environment

- hyprtoolkit 0.5.4 (rev `be487c4`, 2026-08-11), hyprpolkitagent 0.1.3 (rev `7d8031c`)
- Hyprland 0.56.2, monitor 3840x2160 @ scale 1.5 (fractional)
- NixOS, both built from the upstream flakes

## Reproduction

1. Use any output with a non-integer scale (1.5 shows it reliably).
2. Trigger any polkit prompt (e.g. `run0 true`) so hyprpolkitagent opens its dialog.
3. The H2 header "Authentication Required" is END-ellipsized. Every other text in the
   dialog renders fine — all of them carry an explicit `clampSize` (see "Why only
   unclamped text" below).

## Trace evidence (`HT_TRACE=1`)

The header text element renders twice:

```
TextImpl: scheduling rendering of text "Authentication Requi...":
  font: Roboto, fontSize: 15, maxSize: [215, 24], ellipsize: true, wrap: true
TextImpl: got a tex with size [215, 24]

# fractional scale 1.5 arrives:
TextImpl: scheduling rendering of text "Authentication Requi...":
  font: Roboto, fontSize: 23, maxSize: [322.5, 36], ellipsize: true, wrap: true
TextImpl: got a tex with size [323, 37]
```

- First render (scale 1.0): the auto-sized parent row hands the text a room hint of
  `{215, 24}` — precisely the text's own preferred size, so it is already a hard,
  zero-slack clamp with `ellipsize: true` (both hint components ≥ 0).
- Scale change: the font becomes `round(15 × 1.5) = 23px` — an *effective 15.33px
  logical*, ~2.2% wider — and pango's per-pixel-size hinting means the re-measured
  width essentially never lands at exactly 1.5× the old measure. The stale hint is
  only multiplied by the scale (`322.5`), the new desired width exceeds it, and
  `prepPangoLayout` clips via `pango_layout_set_width(min(...))` +
  `PANGO_ELLIPSIZE_END`.

## Where in the code

- `src/element/text/Text.cpp`, `CTextElement::reposition()`: `lastMaxSize` is set from
  the `maxSize` hint (or from the assigned box when no hint is given). The comment
  there already acknowledges the feedback-loop hazard for auto-sized labels; the
  scale-change case is that hazard made permanent.
- `src/element/text/Text.cpp`, `STextImpl::prepPangoLayout()`:
  `data.clampSize.value_or(lastMaxSize)` — the stale hint becomes the pango clamp,
  and `maxSize->y >= 0` turns on END-ellipsis.
- Ellipsized-text `scheduleReposition(impl->self)` only repositions the text's own
  subtree with the same box; the auto-sized ancestor whose size derived from the old
  preferred is never invalidated, so the layout never re-grows.

## Why only unclamped text

An explicit `clampSize({w, -1.0})` keeps `maxSize.y < 0`, which disables ellipsis and
leaves the text in wrap mode — which is why every clamped label in hyprpolkitagent's
dialog is immune and only the header (the one text built without `clampSize`) breaks.

## Workaround

Agent-side one-liner (we currently carry this as a distro patch): clamp the header
like the dialog's other texts —

```cpp
wrap->addChild(CTextBuilder::begin()
                   ->text(std::string{"Authentication Required"})
                   ->fontSize({CFontSize::HT_FONT_H2})
                   ->clampSize({(double)cfg.passwordFieldWidth, -1.0})   // added
                   ...
```

That is a band-aid; the toolkit-level stale-hint behavior affects any unclamped
auto-sized text in any hyprtoolkit app on fractional-scale outputs.

## Suggested direction

Two complementary fixes (details available on request):

1. Make text measurement scale-invariant: pass the fractional font size to pango
   without rounding to whole pixels (pango accepts `PANGO_SCALE` fractional units),
   and measure with metrics hinting disabled, so logical extents match across scales.
2. On a window scale change, invalidate `lastMaxSize` on text elements and relayout
   from the root (as a configure does), so auto-sized ancestors re-query the new
   preferred sizes instead of re-hinting stale boxes.
