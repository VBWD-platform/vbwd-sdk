# Sprints — 2026-05-17 — Hotel exhibition header: chrome divergence from `/home2`

**Trigger:** On prod `hotel.vbwd.cc/` (and every marketing page) the site
header rendered as a grey, full-width bordered bar with a tight bold menu
and a left-flush breadcrumb — visually divergent from the clean,
theme-default header on `hotel.vbwd.cc/home2`. User asked to make the
header (and breadcrumb justification) match `/home2`.

**Class:** Presentation-layer regression introduced by a marketing-content
generator change ("yesterday's styles import"). A per-page/style CSS
override was re-styling layout chrome that is otherwise owned by the
canonical CMS theme stylesheet.

**Scope note (core vs plugin):** Zero core and zero plugin code changed.
The fix lives entirely in marketing content tooling
(`docs/marketing/cms-imports/_generate.py`) and a single prod CMS **Style**
record. No `vbwd-backend/`, no `vbwd-fe-*` source touched — consistent with
"core is agnostic" and "plugins live in their own repos".

## Sprint index

| # | Sprint | Failure class | Effort |
| --- | --- | --- | --- |
| [01](./01-hotel-exhibition-header-chrome.md) | Exhibition style overrode theme header chrome; breadcrumb misaligned | CSS override / layout harmonisation | S |

## Outcome

GREEN. Prod `vbwd-hotel-exhibition` style updated via
`PUT /api/v1/admin/cms/styles/<id>`; header now pixel-matches `/home2`
(`navX=170, navW=1100, menuX=170`) and breadcrumb first-crumb shares the
exact vertical line as the menu's first item (`x=186` on both). Verified
by Playwright computed-style probes + screenshots, desktop and mobile.
Source generator fixed so future seeds reproduce the corrected CSS.
