# Sprint 26 — CMS default style (TDD-driven)

**Status:** DRAFT — awaiting approval before any code changes.
**Date:** 2026-04-20
**Repos touched:**
- `vbwd-plugin-cms` (backend plugin — model, migration, service, routes, tests)
- `vbwd-fe-admin-plugin-cms` (admin UI — list column, editor toggle, page-editor hint)
- `vbwd-fe-user-plugin-cms` (user app — default-style fallback)
- `vbwd-sdk` umbrella (sprint doc + submodule bumps)

Core repos (`vbwd-backend`, `vbwd-fe-admin`, `vbwd-fe-user`) are NOT
modified — all changes stay inside plugins.

## Goal

Let an admin mark **one** CMS style as **default**. Any page whose
`style_id` is NULL falls back to the default style at render time. Pages
with an explicit `style_id` keep winning — the default never overrides
an explicit choice.

## Why now

Today each page either references a specific style or renders with no
stylesheet. The theme-switcher takes over in the "no style" case, which
isn't what most demos want. A designated default style gives every
"stock" page a consistent look without the admin having to assign a style
to every one of them.

## Current state (quick recon)

```
CmsStyle (cms_style)
  id UUID, slug str UK, name str, source_css text, sort_order int,
  is_active bool, created_at, updated_at

CmsPage (cms_page)
  ...
  style_id UUID NULL → cms_style.id ON DELETE SET NULL
  use_theme_switcher_styles bool default True
```

- `/api/v1/cms/styles/<id>/css` — public CSS fetch (used by fe-user).
- fe-user's `useCmsStore.loadPage` eagerly calls `fetchStyleCss` only
  when the page has a non-null `style_id`. Otherwise `currentStyleCss`
  stays empty and the theme-switcher's CSS takes over.
- fe-admin `CmsStyleList.vue` lists styles; `CmsStyleEditor.vue` edits
  them. No notion of "default" anywhere.

## Non-goals

- No change to the theme-switcher plugin. It keeps firing when a page
  ends up with NO CSS (neither explicit nor default).
- No cascade behaviour across styles (no inheritance, no variants).
- Default-style promotion is a **manual** admin action; never automatic.
- No per-category default in this sprint — one global default only.

## Behaviour spec

### Promotion
- An admin promotes a style to default via a button on the edit page or
  a PATCH-like endpoint. Promoting style B when A is currently default
  auto-demotes A in the same transaction.
- Deleting the default style clears the flag (ON DELETE SET NULL on
  `cms_style.id` already handles it; no cascade side-effect on the
  `is_default` column because the row is gone).

### Resolution at render time
- `page.style_id` is not null → page uses that style (unchanged).
- `page.style_id` is null AND a default style exists AND the default is
  `is_active=True` → page uses the default.
- `page.style_id` is null AND no default (or default is inactive) →
  no CSS override; theme-switcher takes over (unchanged).

### Uniqueness guarantee
- At most one row in `cms_style` has `is_default=True`.
- Enforced at two layers:
  1. **Service** — `set_default` unsets the previous default before
     setting the new one, all in one session transaction.
  2. **DB** — partial unique index
     `CREATE UNIQUE INDEX ix_cms_style_default_singleton
      ON cms_style ((is_default)) WHERE is_default IS TRUE;`
     Guards against stray writes outside the service.

## Test-first plan

Every change below is preceded by a failing test. Commits will follow
the strict "red → green → refactor" pattern; PR / history shows the
test commit preceding the implementation commit.

### Unit: `plugins/cms/tests/unit/services/test_cms_style_service.py`
1. **`test_new_style_is_not_default_by_default`**
   `create_style(...)` → `is_default is False` in returned dict.
2. **`test_set_default_promotes_style_and_demotes_previous`**
   Promote A → A.is_default=True. Promote B → B.is_default=True,
   A.is_default=False. Exactly one row has is_default=True.
3. **`test_set_default_on_missing_style_raises_not_found`**
4. **`test_clear_default_unsets_flag`** — `clear_default()` returns
   silently; `get_default_style()` returns None.
5. **`test_get_default_style_returns_none_when_unset`**
6. **`test_get_default_style_returns_style_when_set`**
7. **`test_update_style_is_default_field_respects_single_default`**
   If we PUT `is_default=true` on B while A is default, A is demoted.
8. **`test_inactive_default_is_still_returned_by_get_default`**
   (Behaviour defined by spec — we return it; resolver layer decides
   whether to use it.)

### Unit: `plugins/cms/tests/unit/services/test_cms_page_service.py`
9. **`test_get_page_by_slug_adds_resolved_style_id_when_explicit`**
   Page with `style_id=S` → response has
   `resolved_style_id=S, resolved_style_source="explicit"`.
10. **`test_get_page_by_slug_uses_default_when_page_style_is_null`**
    Default is set + active. Page has `style_id=None`.
    → `resolved_style_id=<default>.id, resolved_style_source="default"`.
11. **`test_get_page_by_slug_no_default_and_no_page_style`**
    Both null/unset. → `resolved_style_id=None,
    resolved_style_source=None`. No error.
12. **`test_default_ignored_when_inactive`**
    Default exists but `is_active=False`. Page has null style.
    → `resolved_style_id=None`.

### Integration / route: `plugins/cms/tests/unit/routes/test_cms_style_routes.py`
13. **`test_post_admin_styles_default_promotes`** —
    `POST /api/v1/admin/cms/styles/<id>/default` returns 200, old
    default (if any) is demoted in DB, `is_default` flag flips.
14. **`test_delete_admin_styles_default_clears`** —
    `DELETE /api/v1/admin/cms/styles/default` returns 200 and clears.
15. **`test_get_public_default_style_css_serves_css`** —
    `GET /api/v1/cms/styles/default/css` → `text/css` body matches
    the default's `source_css`.
16. **`test_get_public_default_style_css_404s_when_no_default`**
17. **`test_list_styles_exposes_is_default_flag`** — admin list returns
    `is_default` on each item and exactly one has `is_default=True`
    when one is promoted.

### fe-admin unit: `plugins/cms-admin/tests/unit/`
18. **`test_cms_style_list_renders_default_badge`** — style with
    `is_default=true` shows the badge.
19. **`test_cms_style_editor_emits_set_default_on_click`** — clicking
    "Set as default" dispatches the store action hitting the API.
20. **`test_cms_page_editor_shows_default_hint_when_style_none`**
    — "Using default style: <name>" text visible.

### fe-admin E2E (existing Playwright set, one new spec)
21. **`cms-style-default.spec.ts`** — walk: login → Styles list →
    open style → click "Set as default" → back to list → assert
    badge on that style + no badge on others.

### fe-user unit: `plugins/cms/tests/unit/`
22. **`useCmsStore_falls_back_to_default_style_when_page_style_null`**
    — mock API: page returns `resolved_style_id=D`; store fetches
    `/api/v1/cms/styles/D/css` and `currentStyleCss` is populated.

### fe-user E2E
23. **`cms-default-style-applied.spec.ts`** (against local demo) —
    visit a page without explicit style; assert the `<style>` tag
    contains the default style's CSS.

## Implementation steps (after each test is red, make it green)

### Backend — `vbwd-plugin-cms`

- **Migration** `20260420_cms_style_is_default.py`
  ```sql
  ALTER TABLE cms_style ADD COLUMN is_default BOOLEAN NOT NULL DEFAULT FALSE;
  CREATE UNIQUE INDEX ix_cms_style_default_singleton
    ON cms_style ((is_default)) WHERE is_default IS TRUE;
  ```
- **Model** `cms_style.py`
  - add `is_default = db.Column(db.Boolean, nullable=False, default=False)`
  - `to_dict()` includes `is_default`.
- **Repository** `cms_style_repository.py`
  - `find_default() -> Optional[CmsStyle]`
- **Service** `cms_style_service.py`
  - `set_default(style_id) -> dict` (demotes existing default in same
    session, promotes target, raises `CmsStyleNotFoundError`).
  - `clear_default() -> None` (idempotent).
  - `get_default_style() -> Optional[dict]`
  - `update_style` passes through `is_default`, delegating to
    `set_default` when transitioning to `True` to preserve uniqueness.
- **Page service** `cms_page_service.py`
  - `_with_resolved_style(page_dict) -> dict` helper that adds
    `resolved_style_id` + `resolved_style_source`. Called from every
    public page getter (`get_page_by_slug`, `get_pages`, admin get).
- **Routes** `routes.py`
  - `POST /api/v1/admin/cms/styles/<style_id>/default` → `set_default`
  - `DELETE /api/v1/admin/cms/styles/default` → `clear_default`
  - `GET /api/v1/cms/styles/default` → public default info
  - `GET /api/v1/cms/styles/default/css` → public CSS (404 if unset)

### fe-admin — `vbwd-fe-admin-plugin-cms`

- **Store** (`cmsStyleAdmin.ts` or similar):
  - action `setDefault(id)` → POST `/admin/cms/styles/<id>/default`
  - action `clearDefault()` → DELETE `/admin/cms/styles/default`
  - exposes `isDefault(id)` selector.
- **`CmsStyleList.vue`**:
  - New column "Default". Badge shown where `is_default=true`.
  - Inline action button "Make default" on non-default rows
    (permission-gated, same as bulk actions).
- **`CmsStyleEditor.vue`**:
  - New "Default" section with a button "Set as default" (disabled
    if already default) + "Clear default" (visible only when this
    style is the default).
- **`CmsPageEditor.vue` (or whatever edits page.style_id)**:
  - When the style select is "(none)", show a hint below it:
    "Using default style: *<name>*". If no default, show "No default
    style configured — theme-switcher will render this page."

### fe-user — `vbwd-fe-user-plugin-cms`

- **Store** `useCmsStore.ts`:
  - Read `resolved_style_id` from the page response. If set, fetch
    that CSS; else skip (unchanged behaviour).
  - Remove the existing `style_id` branch in favor of
    `resolved_style_id` (backwards-compatible — backend always emits
    both; if `resolved_style_id` is missing on old backends, fall
    back to `style_id`).

## Files changed (by repo)

```
vbwd-plugin-cms/
  alembic/versions/20260420_cms_style_is_default.py            NEW
  src/models/cms_style.py                                      MOD
  src/repositories/cms_style_repository.py                     MOD
  src/services/cms_style_service.py                            MOD
  src/services/cms_page_service.py                             MOD   (resolver)
  src/routes.py                                                MOD   (4 new routes)
  tests/unit/services/test_cms_style_service.py                MOD   (+tests 1–8)
  tests/unit/services/test_cms_page_service.py                 MOD   (+tests 9–12)
  tests/unit/routes/test_cms_style_routes.py                   MOD   (+tests 13–17)

vbwd-fe-admin-plugin-cms/
  src/stores/cmsStyleAdmin.ts                                  MOD
  src/views/CmsStyleList.vue                                   MOD
  src/views/CmsStyleEditor.vue                                 MOD
  src/views/CmsPageEditor.vue                                  MOD
  tests/unit/CmsStyleList.spec.ts                              NEW  (test 18)
  tests/unit/CmsStyleEditor.spec.ts                            NEW  (test 19)
  tests/unit/CmsPageEditor.spec.ts                             MOD  (test 20)
  tests/e2e/cms-style-default.spec.ts                          NEW  (test 21)

vbwd-fe-user-plugin-cms/
  src/stores/useCmsStore.ts                                    MOD
  tests/unit/useCmsStore.spec.ts                               MOD  (test 22)
  tests/e2e/cms-default-style-applied.spec.ts                  NEW  (test 23)

vbwd-sdk/
  docs/dev_log/20260403/sprints/26-cms-default-style.md        NEW  (this file)
  vbwd-fe-user, vbwd-fe-admin                                  submodule bumps
```

## Commit order (TDD discipline)

1. backend: tests 1–12 red → commit "red"
2. backend: migration + model + service + page-service green → commit "green"
3. backend: tests 13–17 red → commit
4. backend: routes green → commit
5. fe-admin: tests 18–20 red → commit
6. fe-admin: store + views green → commit
7. fe-admin: E2E spec 21 → commit (skipped on CI until deploy)
8. fe-user: test 22 red → commit
9. fe-user: store change green → commit
10. fe-user: E2E spec 23 → commit
11. sdk: sprint doc + submodule bumps → commit

Each commit runs `bin/pre-commit-check.sh --unit` (backend) or
`pre-commit-check.sh --unit` (fe-*) before pushing.

## Rollout

1. Merge + push plugin repos. CI triggers image rebuilds through the
   demo-instances workflow.
2. Run the deploy workflow with `run_migrations: true` — the new
   Alembic migration adds the column + partial index.
3. In admin UI, promote a style on `main` (and any other vertical) to
   verify end-to-end.
4. Remove the temporary `style_id` branch in fe-user's useCmsStore in a
   follow-up once every backend instance is confirmed emitting
   `resolved_style_id`.

## Acceptance

- All 23 tests green on CI.
- Promoting style B while A is default demotes A atomically — observable
  via two admin UI badges not both on.
- A brand-new page with no style_id renders the default CSS on the
  public site; if no default exists, renders with theme-switcher as
  today.
- Partial unique index present in live DB; trying to `UPDATE ... SET
  is_default=true` on two rows outside the service rolls back.

## Effort

- Backend (migration + service + routes + tests): ~3h
- fe-admin (store + 3 views + 3 unit tests + 1 E2E): ~3h
- fe-user (store + 1 unit + 1 E2E): ~1h
- Docs + submodule bumps: ~0.5h

Total: **~7.5 hours** across one deploy cycle.

## Approval gate

No code until you reply "go". If you want any behaviour change (e.g.
**auto-promote** the only remaining style when the current default is
deleted, or surface default-source=default/explicit in the admin page
editor differently), flag it before approval.
