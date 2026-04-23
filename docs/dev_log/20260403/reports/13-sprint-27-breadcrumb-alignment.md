# Report — Sprint 27 follow-up: breadcrumb alignment + symmetric separator

**Date:** 2026-04-22
**Repo touched:** `vbwd-sdk` / `vbwd-backend/plugins/cms/docs/imports/_build_theme_styles.py`
**Status:** ✅ Merged, theme-styles.json rebuilt, CMS DB re-populated.

## Problem

On every theme, the breadcrumb row under the header exhibited two visual defects:

1. The first crumb ("Home") did not sit on the same vertical line as the burger-menu icon. The burger icon's SVG was at `--edge-inset` (thanks to the `margin-left: -6px` cancelling the button's 6px padding), while the breadcrumb's first `<a>` was typically inset further right due to the breadcrumb widget's own `display: flex; gap: 4px; padding: 8px 0 0.25rem` config CSS plus whatever residual spacing the first flex child inherited.
2. The "/" separator between crumbs had visibly asymmetric spacing — more white space on one side of the glyph than the other — because `gap: 4px` feeds the same 4px into both neighbours but the glyph itself has asymmetric side bearings (the "/" leans right, so the perceived gap on its left grows and on its right shrinks).

User-provided screenshot (arrow pointed at the "/" glyph) showed the visible imbalance.

## Fix

All changes in `vbwd-backend/plugins/cms/docs/imports/_build_theme_styles.py` (the source-of-truth builder for the 21-theme matrix). Rebuilt `theme-styles.json` and ran `plugins/cms/bin/populate-db.sh` to upsert every style row.

### New rules injected into every theme's base CSS

```css
/* Breadcrumb layout: zero flex gap and use explicit symmetric margins on
 * the separator so "X / Y" always has identical spacing on both sides of
 * the "/" glyph. First visible link sits flush with the wrapper's
 * content-left edge — same vertical line as the burger icon. */
.cms-breadcrumb { gap: 0 !important; }
.cms-breadcrumb a,
.cms-breadcrumb__link,
.cms-breadcrumb__current {
  margin: 0 !important;
  padding: 0 !important;
}
.cms-breadcrumb__separator {
  margin: 0 0.5rem !important;
  padding: 0 !important;
  display: inline-block;
  text-align: center;
}
.cms-breadcrumb > a:first-of-type,
.cms-breadcrumb > .cms-breadcrumb__link:first-of-type {
  margin-left: 0 !important;
  padding-left: 0 !important;
}
```

Why each rule:

- **`gap: 0 !important`** — kills flex gap so spacing around the separator is driven by explicit margins, not by the neighbour-to-neighbour gap algorithm. This is the only way to get provably symmetric spacing either side of the glyph regardless of font bearings.
- **All links/current → `margin: 0; padding: 0`** — strips any user-agent or scoped-CSS leftovers from `<a>` / `<router-link>` / `<span>` children.
- **Separator → `margin: 0 0.5rem` + `display: inline-block; text-align: center`** — 8px of space on the left and 8px on the right of the separator's box, with the glyph centred inside its own box. The inline-block switch is what makes the box width deterministic so both halves of the surrounding margin hit the same visual distance.
- **First-of-type link → `margin-left: 0; padding-left: 0`** — hedges against any widget-level `.cms-breadcrumb__link:first-child` rule that might try to indent. Combined with the existing parent rule `.cms-breadcrumb { padding-left: var(--edge-inset) !important; }`, this guarantees the "H" in "Home" lands exactly at the page's `--edge-inset` line — which is the same line the burger icon's visual left edge lands on.

### Why the burger alignment works

`.cms-widget--header-nav .cms-burger { margin-left: -6px; }` was already in the theme. The burger is a `<button>` with `padding: 6px`, so its bounding-box left is at `edge-inset - 6px`, but the SVG it wraps is at `edge-inset - 6px + 6px = edge-inset`. The breadcrumb's first link text now starts at `edge-inset` too, so the two sit on the same vertical line.

## Verification

Measured with Playwright on `http://localhost:8080/enterprise` at viewport 1440×900:

```
burger_left:         34   (button outer edge)
burger_icon_left:    40   (via 6px internal padding → edge-inset)
first_link_left:     40   ← identical to burger icon
sep_before:          8px  (space between "Home" and "/")
sep_after:           8px  (space between "/" and next link)
```

Screenshot comparison (`test-results/breadcrumb-verify.png`) confirmed the "H" in "Home" sits directly under the left edge of the burger's three-line icon, and the "/" has visually equal padding on both sides.

## Propagation

- Re-ran `_build_theme_styles.py` — regenerated `theme-styles.json` (21 themes).
- Re-ran `plugins/cms/bin/populate-db.sh` — upserted every style row, so all existing light/dark themes in the DB now carry the new rules.
- No data migration needed; the column is TEXT and the upsert overwrites `source_css`.
- Experimental themes under `/docs/marketing/cms-imports/shop/themes/_build_experimental.py` inherit the same base rules via their own build step — no change needed there, but a follow-up re-upsert script run is worthwhile.

## Files changed

- `vbwd-backend/plugins/cms/docs/imports/_build_theme_styles.py` (lines ~141-164 — replaced the `.cms-breadcrumb > :first-child` one-liner with the rule block above)
- `vbwd-backend/plugins/cms/docs/imports/theme-styles.json` (regenerated)
- DB: `cms_style.source_css` for all 21 rows (upserted via populator)

## Follow-ups

None critical. Optional polish:

- Widget config CSS in `docs/imports/widgets/breadcrumbs.json` still contains the original `gap: 4px; padding: 8px 0 0.25rem` rules. They're now effectively inert (the theme CSS overrides them with `!important`). A future cleanup could strip them from the widget config so the widget ships less no-op CSS, but it isn't necessary.
