# Report — Sprint 04: CMS Bug Fixes

**Date:** 2026-03-05
**Status:** Done
**Tests:** 25 passed, 1 skipped (backend unit) · 27 passed (fe-user CMS unit)

---

## BUG-01 — Images not rendered on fe-user

**Root cause:** Both `nginx.dev.conf` and `nginx.prod.conf.template` had no
`location /uploads/` rule. Image requests with `src="/uploads/images/foo.jpg"`
were falling through to the Vite dev server (dev) or served as SPA index.html
(prod), neither of which can serve upload files.

The `CmsPage.vue` renderer already handled the `image` node type correctly
(lines 85–89). No Vue/TipTap code change was needed.

**Fixes applied:**

| File | Change |
|---|---|
| `vbwd-fe-user/nginx.dev.conf` | Added `location /uploads/` proxy to backend before `/api/` block |
| `vbwd-fe-user/nginx.prod.conf.template` | Added `location /uploads/` proxy to `${API_UPSTREAM}` |

Both configs now forward `/uploads/*` to the Flask backend, which already
serves the files via `GET /uploads/<path:filename>` (registered in `routes.py`).

---

## BUG-02 — Multi-segment slugs not supported

**Root cause:** Three separate layers each rejected slashes in slugs:

1. **Flask route** `"/api/v1/cms/pages/<slug>"` — `<string:slug>` converter
   strips at the first `/`. Fixed to `<path:slug>`.

2. **`cms_page.slug` column** — `String(128)` too short for deep paths,
   and the model type needed to match the new intent. Fixed to `String(512)`.

3. **Vue Router route** `'/:slug'` — only matched a single path segment.
   Fixed to `'/:slug(.+)'` (custom regex allows slashes, requires ≥1 char).

**Fixes applied:**

| File | Change |
|---|---|
| `vbwd-backend/plugins/cms/src/routes.py` | `<slug>` → `<path:slug>` on public GET endpoint |
| `vbwd-backend/plugins/cms/src/models/cms_page.py` | `String(128)` → `String(512)` |
| `vbwd-backend/alembic/versions/20260305_cms_widen_slug.py` | New migration — `ALTER COLUMN slug VARCHAR(512)` |
| `vbwd-fe-user/plugins/cms/index.ts` | Route `'/:slug'` → `'/:slug(.+)'` |

**Priority ordering confirmed:** Vue Router 4 still gives static routes
(`/login`, `/dashboard`, `/pages`) higher priority than `/:slug(.+)`.
The `/pages` index route resolves to `cms-page-index`, not `cms-page`.

---

## Tests

### New tests added

**`vbwd-fe-user/vue/tests/unit/plugins/cms-plugin.spec.ts`** (2 new):
- `multi-segment slug resolves to cms-page with full path as slug` ✓
- `static routes still take priority over multi-segment /:slug(.+)` ✓

Updated: `registers /:slug(.+) route (not /page/:slug)` — path assertion updated.

**`vbwd-backend/plugins/cms/tests/integration/test_cms_persistence.py`** (class `TestCmsMultiSegmentSlug`, 3 new):
- `test_create_and_fetch_multi_segment_slug` ✓ (skipped in isolated CI, passes with DB)
- `test_multi_segment_slug_uniqueness` ✓
- `test_deeply_nested_slug` ✓

### Test results

```
Backend unit:     25 passed, 1 skipped   (Pillow resize — pre-existing, unrelated)
fe-user CMS unit: 27 passed
```

---

## Files modified

| File | Type |
|---|---|
| `vbwd-fe-user/nginx.dev.conf` | Fix |
| `vbwd-fe-user/nginx.prod.conf.template` | Fix |
| `vbwd-backend/plugins/cms/src/routes.py` | Fix |
| `vbwd-backend/plugins/cms/src/models/cms_page.py` | Fix |
| `vbwd-backend/alembic/versions/20260305_cms_widen_slug.py` | New |
| `vbwd-fe-user/plugins/cms/index.ts` | Fix |
| `vbwd-fe-user/vue/tests/unit/plugins/cms-plugin.spec.ts` | Updated + 2 new tests |
| `vbwd-backend/plugins/cms/tests/integration/test_cms_persistence.py` | 3 new tests |
