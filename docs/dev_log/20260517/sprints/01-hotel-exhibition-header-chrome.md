# Sprint 01 — Hotel exhibition style overrode theme header chrome

**Status:** IMPLEMENTED & VERIFIED — 2026-05-17
**Result:** Prod header on `hotel.vbwd.cc/` now matches `/home2` exactly.
Source generator (`docs/marketing/cms-imports/_generate.py`) corrected;
all five verticals' `pages.json` regenerated; prod CMS Style
`vbwd-hotel-exhibition` (`4c20328b-0893-45a9-94ab-eff802dad7ba`) updated
in place via the admin API. Header-nav box `x=170 w=1100` and menu
`x=170` identical between `/` and `/home2`; breadcrumb first crumb and
menu first item both start at `x=186` (harmonical vertical line).
**Repos:** SDK only — `docs/marketing/cms-imports/` (no core/plugin code).
**Deployment:** prod Style record PUT (one row); no pages deleted, no
container redeploy. Reversible.
**Severity:** Medium — cosmetic, but on every public marketing page of a
production demo instance.

---

## 1. Failure analysis (root cause, not symptom)

### Observed

`hotel.vbwd.cc/` → redirects to slug `home` → grey full-width header bar
with `border-bottom`, tight bold menu, breadcrumb flush to column edge.
`hotel.vbwd.cc/home2` → transparent header, no border, 16px/500 links,
centred 1100px column, no breadcrumb. Same site, same theme.

### Why they differed

`/home2` (layout `home-v2`, **no** page style) inherits layout chrome
from the canonical theme stylesheet
(`vbwd-backend/plugins/cms/docs/imports/_build_theme_styles.py`), which
sets header-nav/footer-nav/breadcrumb to
`max-width: var(--container-max); margin: auto` and leaves them visually
clean.

`/` (slug `home`) is assigned CMS **Style** `vbwd-hotel-exhibition`. That
style's `source_css` is the output of
`docs/marketing/cms-imports/_generate.py :: build_css()`. A prior change
had appended a `/* Layout chrome (header / breadcrumbs / footer) */`
block to `BASE_CSS_TEMPLATE`:

```css
.cms-layout .cms-area--header { background:#fff; border-bottom:1px solid #e2e8f0; }
.cms-layout .cms-area--header .cms-widget--header-nav { max-width:1100px; margin:0 auto; padding:0.9rem 1.5rem; }
.cms-layout .cms-widget--header-nav .cms-menu { gap:1.75rem; }
.cms-layout .cms-widget--header-nav .cms-menu__link { color:#0f172a; font-weight:600; font-size:0.95rem; }
.cms-layout .cms-area--vue { max-width:1100px; margin:0 auto; padding:0.6rem 1.5rem 0; }
.cms-layout .cms-area--footer { border-top:1px solid #e2e8f0; background:#fff; }
/* + footer-nav width + responsive */
```

Because exhibition pages set `use_theme_switcher_styles: false`, they
never load the theme chrome rule — so this block was the *only* chrome
styling, and it diverged from the theme. The page's own `source_css` was
already clean; the bad CSS lived solely in the Style record.

### The deployment subtlety that mattered

`CmsPageService.import_pages` is **create-only** — existing slugs are
skipped, never updated (`README.md`: "To replace a page, delete it first
or bump its slug"). So re-running `import.sh` against prod would NOT have
fixed anything. The live divergence lived in a **Style** row, not a Page;
the correct surgical lever was `PUT /api/v1/admin/cms/styles/<id>` with
`{"source_css": ...}`, touching exactly one row.

## 2. Fix

`docs/marketing/cms-imports/_generate.py` — `BASE_CSS_TEMPLATE`:

1. Removed the entire cosmetic chrome block (background, border, padding,
   `gap`, link weight/colour). Chrome cosmetics belong to the theme.
2. Re-asserted **only geometry** so exhibition pages (which don't load
   the theme) still centre the chrome like `/home2`:

   ```css
   .cms-layout .cms-widget--header-nav,
   .cms-layout .cms-widget--footer-nav,
   .cms-layout .cms-area--vue .cms-breadcrumb {
     max-width: 1100px; margin-left: auto; margin-right: auto;
   }
   ```
3. Harmonised the breadcrumb: every `.cms-menu__link` has 16px intrinsic
   left padding, so the menu's first item text sits 16px inside the
   column. The breadcrumb had no per-item padding → started 16px too far
   left. Added:

   ```css
   .cms-layout .cms-area--vue .cms-breadcrumb { padding-left: 16px; }
   ```

Then: `python3 docs/marketing/cms-imports/_generate.py` (regenerates
`pages.json` for core/softwarestore/hotel/doctor/ghrm); rebuilt
`build_css(VERTICALS['hotel'])`; `PUT` the result onto the prod
`vbwd-hotel-exhibition` style.

## 3. Verification

Playwright computed-style + range-rect probes against live prod:

| Metric | Before | After `/` | `/home2` |
| --- | --- | --- | --- |
| header area bg | `#fff` | transparent | transparent |
| header border-bottom | `1px #e2e8f0` | `0` | `0` |
| header-nav box | `x=16 w=1408` | `x=170 w=1100` | `x=170 w=1100` |
| menu gap | `28px` | `normal` | `normal` |
| link size/weight | `15.2px/600` | `16px/500` | `16px/500` |
| menu "Home" text x | — | `186` | `186` |
| breadcrumb first-crumb x | `170` | `186` | n/a (none) |

Screenshots captured desktop (1440) + mobile (390) for `/`, `/about`,
`/home2` — all confirm a clean transparent header and aligned breadcrumb.

## 4. Follow-ups / notes

- `_generate.py` regenerated `pages.json` for **all five verticals**;
  only `hotel` was deployed. Others are source-only until imported.
- Prod's `home` page sources chrome from the **Style** row, not from
  `pages.json`/`home.json`. The durable guarantee is: if the instance is
  re-seeded from `_generate.py`, it now produces the corrected CSS.
- No commit made (standing preference: SDK changes left in working tree
  for review).
