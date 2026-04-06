# Sprint 04 — CMS Bug Fixes: Image Rendering & Multi-Segment Slugs

**Date:** 2026-03-05
**Principles:** TDD-first · SOLID · DRY · Clean Code
**Dependencies:** `cms` plugin (Sprint 01), `cms-slug-routing-fix` (Sprint 02 done)

---

## Overview

Two bugs in the existing CMS plugin to fix before proceeding with Sprint 03 templating work:

- **BUG-01** — Images inserted in the TipTap page editor are not rendered on the fe-user frontend
- **BUG-02** — CMS page slugs must support multi-segment paths (e.g. `blog/2026/my-article`)

---

## BUG-01 — CMS page image not rendered on fe-user

**Symptom:** An image added in the admin page editor
(`/admin/cms/pages/<id>/edit`) is visible in the editor but does not appear
when visiting the published page on fe-user (e.g. `/test2`).

**Likely causes to investigate in order:**

| # | Cause | Fix |
|---|---|---|
| 1 | `Image` TipTap extension missing from `generateHTML()` call in `CmsPage.vue` | Add `Image` to the extensions array used for rendering |
| 2 | `/uploads/` path not served by fe-user nginx — bind-mount missing | Verify `vbwd-fe-user/docker-compose.yaml` has the uploads volume + nginx `location /uploads/` |
| 3 | `content_json` not included in PUT payload on save | Ensure `CmsPageEditor.vue` sends both `content_json` and `content_html` |

**Investigation order:** check browser DevTools network tab on the slug page —
if the `<img>` tag is present in DOM but broken, it is cause #2; if no `<img>`
tag at all, it is cause #1 or #3.

### Backend fix (if needed)

No model changes expected. If cause #3 is confirmed:

```python
# plugins/cms/src/routes.py — PUT /api/v1/admin/cms/pages/<id>
# Ensure content_json is read from request body and passed to service
```

### fe-user fix (cause #1)

```typescript
// vbwd-fe-user/src/plugins/cms/CmsPage.vue
import { generateHTML } from '@tiptap/html'
import StarterKit from '@tiptap/starter-kit'
import Image from '@tiptap/extension-image'   // <-- add this

const html = generateHTML(page.content_json, [
  StarterKit,
  Image,   // <-- add this
])
```

### fe-user fix (cause #2)

```nginx
# vbwd-fe-user/nginx.conf or docker-compose.yaml
location /uploads/ {
    alias /usr/share/nginx/html/uploads/;
}
```

```yaml
# vbwd-fe-user/docker-compose.yaml
volumes:
  - /loopai_storage/vbwd/uploads:/usr/share/nginx/html/uploads:ro
```

### Tests

```
plugins/cms/tests/integration/
  test_cms_pages_api.py
    + test_page_content_json_preserves_image_node
        create page with content_json containing image node
        GET page → assert image node present in response content_json

vbwd-fe-user/tests/unit/
  CmsPage.spec.ts
    + test_renders_img_tag_from_content_json_image_node
        mount CmsPage with content_json containing image node
        assert rendered HTML contains <img src="...">

vbwd-fe-user/tests/e2e/
  cms-image-render.spec.ts
    + test_image_visible_on_published_page
        POST page with image via API → visit /:slug → assert <img> visible
```

---

## BUG-02 — CMS slugs must support multi-segment paths

**Requirement:** A page slug is a single unique flat string that may contain
forward slashes. It is not a hierarchy — just one opaque identifier per page.

```
# Valid slugs
test2
blog/2026/my-article
something/anothersomething/something_else
```

### Backend fix

**1. Migration — widen slug column**

```python
# alembic/versions/20260305_cms_widen_slug.py
op.alter_column('cms_page', 'slug', type_=sa.String(512))
```

**2. Route — use `<path:slug>` converter**

Flask's default `<string:slug>` rejects forward slashes.
`<path:slug>` accepts them:

```python
# plugins/cms/src/routes.py
@bp.route("/cms/pages/<path:slug>", methods=["GET"])
def get_page_by_slug(slug):
    ...
```

No change to the service or repository layer — slug is just a string.

### fe-user fix

Vue Router's `/:slug` only matches a single path segment.
Change the CMS catch-all route to match any path, and ensure it is
registered **last** so it does not swallow other plugin routes:

```typescript
// vbwd-fe-user/src/plugins/cms/index.ts  (or wherever routes are registered)
{
  path: '/:slug(.*)',
  name: 'CmsPage',
  component: () => import('./views/CmsPage.vue'),
}
```

`CmsPage.vue` already reads `route.params.slug` — no change needed there.

**Router registration order** (critical):
All other plugin routes (checkout, profile, ghrm, etc.) must be registered
before the CMS catch-all. The `pluginLoader` must guarantee CMS plugin is
installed last, or the catch-all route must be appended after all others.

### Tests

```
plugins/cms/tests/integration/
  test_cms_pages_api.py
    + test_get_page_by_multi_segment_slug
        POST page slug="blog/2026/article" → GET /api/v1/cms/pages/blog/2026/article
        assert 200 + correct page
    + test_multi_segment_slug_uniqueness
        POST page slug="a/b" → POST page slug="a/b" → assert 409

vbwd-fe-user/tests/unit/
  CmsPage.spec.ts
    + test_fetches_page_using_full_multi_segment_slug
        mock route.params.slug = "a/b/c"
        assert API called with slug "a/b/c"

vbwd-fe-user/tests/e2e/
  cms-slug-routing.spec.ts
    + test_multi_segment_slug_renders_correct_page
        create page slug="a/b/c" via API → visit /a/b/c → assert page title
    + test_other_plugin_routes_not_swallowed_by_cms_catchall
        visit /checkout → assert checkout page renders (not CMS 404)
```

---

## Implementation Order (TDD)

```
1.  Write failing integration test: test_page_content_json_preserves_image_node
2.  Investigate & fix BUG-01 (TipTap Image extension / nginx volume / payload)
3.  Unit + E2E tests for BUG-01 pass

4.  Write failing integration test: test_get_page_by_multi_segment_slug
5.  Add Alembic migration: widen cms_page.slug to VARCHAR(512)
6.  Fix Flask route: <string:slug> → <path:slug>
7.  Fix fe-user router: /:slug → /:slug(.*)  (registered last)
8.  All BUG-02 tests pass

9.  Run full pre-commit check:
    make pre-commit-quick  (backend lint + unit)
    make test-integration  (backend integration)
    npm run test           (fe-user unit)
    npm run test:e2e       (fe-user E2E)
```
