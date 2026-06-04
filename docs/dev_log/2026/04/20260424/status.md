# 2026-04-24 — Daily status

## Sprint in flight

- **Sprint 57 — meinchat (nickname + contacts + messaging + token transfer)** — IMPLEMENTED 2026-04-29.
  See [`sprints/57-meinchat.md`](sprints/57-meinchat.md) and the [completion report](reports/03-meinchat-completion.md).
  All three plugin trees built, **158/158 tests green** (128 backend unit + 3 integration + 23 fe-user + 4 fe-admin), backend pre-commit gate SUCCESS. Local instance enabled. Pending operator actions: standalone-repo extraction + prod deploy on `vbwd.cc`.

## Work done today

- **CMS theme pipeline stabilised.**
  - `_build_theme_styles.py` extras loader now reads from `vbwd-backend/plugins/cms/docs/imports/styles/styles/` (single source for both generated matrix and hand-authored themes); regenerated `theme-styles.json` → 27 themes (21 matrix + 6 extras).
  - Burger drawer slides in from the **left** (matching the burger icon position) across all 27 themes + the component's base CSS.
  - Burger button gets `position: relative; z-index: 400` on mobile so its burger → X animation stays visible on top of the open drawer.
  - Local DB patched in place (`UPDATE cms_style …`); no re-import required on localhost.
- **Admin UI improvements.**
  - 401 from API now redirects to `/admin/login?redirect=<previous-path>` instead of rendering "Invalid or expired token". Login view honours the `redirect` query (safelisted to `/admin/*`).
  - CMS Styles admin: zip upload supported (`.json` or `.zip`), `__MACOSX/._*` AppleDouble sidecars ignored, import modes `replace` (upsert by slug) and `copy` (save as `-2, -3`).
- **Backend tests:** all CMS unit tests green (172/173; one unrelated Pillow fixture still failing).

## Pending — needs user action

- **Production (`vbwd.cc` et al.) still has the pre-fix CSS.** Either (a) rebuild backend + fe-admin images and re-upload the themes zip via the prod admin UI, or (b) SSH + the one-liner in the previous chat that patches all five per-instance DBs in place.
- **Push all local commits.** Nothing has been pushed today across:
  - `vbwd-backend` (import-mode + zip + style patches)
  - `vbwd-fe-admin` (401 redirect, import UI, store changes)
  - `vbwd-fe-user` (burger drawer direction, z-index fix)
- **Rotate leaked keys + force-push scrubbed `vbwd-platform`** (carry-over from previous sprint).

## Blockers

None.

## Decisions to confirm before starting Sprint 57

Open questions are listed at the bottom of `sprints/57-nickname-messaging-token-transfer.md` (nickname-change cost, token-transfer minimum, attachment retention, soft-delete semantics, banned-nickname slug reclaim). Default assumptions are noted in-line.
