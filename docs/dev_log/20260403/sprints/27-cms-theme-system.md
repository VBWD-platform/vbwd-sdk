# Sprint 27 — CMS theme system overhaul (TDD-lite)

**Status:** DRAFT — awaiting approval.
**Date:** 2026-04-21
**Repos touched:**
- `vbwd-plugin-cms` — populator rewrite (styles + showcase page + widgets)
- `vbwd-sdk` umbrella — sprint doc only

No changes to fe-admin / fe-user plugins or core repos. The new styles
are consumed via the same `/api/v1/cms/styles/<id>/css` endpoint — client
is style-agnostic.

## Goal

Rebuild the CMS default style catalogue around **6 curated themes**, a
**wider default content width**, and **shared widget primitives** (buttons,
cards, hero, carousel, CTA, quote, typography, columns, lists) that ship
with every theme. Reference implementation:
`docs/marketing/cms-imports/shop/preview.html` — style tokens + widget
layouts are that quality bar.

Ship a **showcase page** that renders every widget in every state so the
admin can preview the theme immediately and designers can see the full
surface they're styling.

## Theme list (final)

| Slug | Label | Family | Accent feel |
|---|---|---|---|
| `light-clean` | Light | Light | neutral cool blue |
| `light-warm` | Light — Warm | Light | amber / terracotta |
| `light-cool` | Light — Cool | Light | teal / slate |
| `dark-ocean` | Dark — Ocean | Dark | deep blue / cyan |
| `dark-purple` | Dark — Purple | Dark | violet / magenta |
| `dark-forest` | Dark — Forest | Dark | emerald / lime |

Replaces the current set of ten (`light-clean`, `light-warm`, `light-cool`,
`light-soft`, `light-paper`, `dark-midnight`, `dark-charcoal`, `dark-forest`,
`dark-purple`, `dark-carbon`). `light-soft`, `light-paper`,
`dark-midnight`, `dark-charcoal`, `dark-carbon` are dropped —
`populate_cms.py` will upsert the 6 and **not delete** the five obsolete
slugs so any admin who picked one keeps working; we mark them as
`is_active=false` so they drop out of "pick a style" menus.

## Width system

Current `--vbwd-container` max-width is `1080px` on the shop preview. We
widen and add tiered variables so widgets can opt in to a wider canvas
without overriding container rules:

```
--vbwd-container-narrow: 720px     /* long-form text, blog posts */
--vbwd-container:        1200px    /* default page width  ← WIDER */
--vbwd-container-wide:   1400px    /* hero, image-heavy */
--vbwd-container-full:   100%      /* edge-to-edge */
```

Every widget declares which tier it uses via a class
(`vbwd-container--wide` etc.). Responsive rules stay identical to the
shop preview (clamp-based padding, stacking on ≤640px).

## Contrast buttons (every theme)

Each theme defines four button variants sharing the same base class:

| Variant | Selector | Use |
|---|---|---|
| standard accent | `.btn.btn--accent` | primary CTA, matches accent colour |
| standard contrast | `.btn.btn--contrast` | HIGH contrast — inverts bg/fg, for dark hero on light theme & vice-versa |
| standard (no accent) | `.btn` | neutral border-only button |
| inactive | `.btn[disabled]` / `.btn.is-disabled` | 0.5 opacity, no hover |

Pattern: themes declare `--vbwd-accent`, `--vbwd-accent-contrast`,
`--vbwd-accent-fg` and the button base CSS is identical across themes —
only variables differ.

## Widget primitives to include

Same set as shop/preview.html, explicit list for the showcase page:

1. **Hero** — gradient background, eyebrow chip, h1, subcopy, dual CTAs
2. **Typography** — h1..h4, paragraph, code, link, blockquote inline sample
3. **Buttons row** — all 4 variants side-by-side
4. **Feature grid** — 3-col card layout with icon + title + copy
5. **Columns** — 2-col and 3-col text blocks with image-right alt variant
6. **Lists** — unordered, ordered, checked-item list
7. **Quote / testimonial** — centered, attributed, with border accent
8. **Carousel** — 3 cards, CSS-only scroll-snap (no JS dependency)
9. **CTA band** — full-width gradient strip with headline + button
10. **Plan table / pricing** — 3-tier comparison card row

All markup is plain HTML that lives inside a single CMS widget
(`widget_type: html`), because that's what the existing renderer knows.
Each widget's `source_css` is scoped with `.vbwd-page` prefix like the
reference preview.html.

## Deliverables

### In `vbwd-plugin-cms/src/bin/populate_cms.py`

1. **STYLES constant** — replace current 10-entry list with 6 new entries.
   Each style's `source_css` is the full widget library (≈15-20 KB after
   minification) driven by CSS custom properties. Shared base + theme
   overrides via `:root.theme-<slug>` OR the style being applied at page
   level (just replace the variables). Keep the structure identical
   across all six so switching themes works with zero layout shift.
2. **Deactivate obsolete styles** — mark `light-soft`, `light-paper`,
   `dark-midnight`, `dark-charcoal`, `dark-carbon` with
   `is_active=false` if they exist (idempotent).
3. **`is_default`** — `light-clean` becomes the initial default
   (via `set_default` CLI-equivalent in the populator).
4. **Showcase page** — new page `slug: showcase`, title "Design system
   showcase", `style_id=null` (uses default), rendering all 10 widget
   categories above. Helper `_make_showcase_widgets()` builds one big
   HTML widget per category; page uses a layout with a single `content`
   area (or reuses `content-page`).

### In `docs/marketing/cms-imports/_generate.py`

1. Add `showcase` to the per-vertical page list.
2. Optionally: emit a standalone `preview.html` per vertical that uses
   each theme so designers can flip between themes visually. This
   preview script already exists for shop; extend to emit one per theme
   and add a theme selector (`<select>` swaps body class).

### Migration

None needed. Styles are data — idempotent upsert via the existing
populator. Fresh DBs get the six; existing DBs see the six new ones
inserted + five old ones deactivated.

## TDD scope (lite)

Full TDD (like sprint 26) is overkill for CSS data. We keep one smoke
integration test:

- **`test_cms_populator_writes_six_active_themes`** — after running the
  populator against a clean DB, `/api/v1/admin/cms/styles` returns
  exactly 6 styles with `is_active=true`, and the expected slugs match.
- **`test_cms_populator_marks_old_themes_inactive`** — if the DB already
  has `dark-charcoal`, a re-run marks it `is_active=false` rather than
  deleting it.
- **`test_showcase_page_exists_and_is_published`** — page with slug
  `showcase` exists and is_published=true.

## Non-goals

- Theme switcher plugin changes — out of scope. This sprint just
  produces the styles; the theme-switcher can pick them up unchanged.
- Per-page theme override in the admin UI — already exists via
  `style_id` on the page editor.
- CSS minification pipeline — ship the CSS uncompressed in `source_css`
  (it's served once with long-cache headers anyway).
- Dark-mode auto-switching via `prefers-color-scheme` — explicit pick
  only, to keep the admin in control.

## Effort estimate

- 6 themes × widget library (mostly token swaps): ~3–4h
- Showcase page + widget builders in populator: ~2h
- Generator preview extension: ~1h
- Smoke tests + populator re-run: ~1h

Total: **~7–8h** plus one deploy cycle.

## Approval gate

Reply "go" to start. If you want a different width tier (e.g.
`1280px` instead of `1200px`) or additional widget types, note it
before I begin.
