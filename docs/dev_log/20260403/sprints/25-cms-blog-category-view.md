# Sprint 25 — CMS blog category view (stub)

**Status:** Stub — scope declared, no code yet.
**Date:** 2026-04-20
**Depends on:** sprint 24 (per-instance seed overlay landed the stub `/blog`
menu link).

## Goal

Make the `/blog` link on vbwd.cc (and any vertical that routes it) land on a
real public blog view: paged list of published pages filtered by one
admin-designated "blog-home" category, with month archive and a search
query param. Category detail pages at `/blog/<category-slug>` share the
same paged/search behaviour.

## Scope

### Backend (plugin `vbwd-plugin-cms`)
- New column `CmsCategory.is_blog_home: bool` with unique partial index
  (only one blog home at a time).
- Admin API: `PUT /api/v1/admin/cms/categories/<id>/blog-home` (promote)
  and `DELETE .../blog-home` (demote).
- Public API additions:
  - `GET /api/v1/cms/blog?page=&per_page=&q=&month=YYYY-MM` → paged pages
    in the blog-home category.
  - `GET /api/v1/cms/blog/archive` → list of `{month, count}` tuples.
  - `GET /api/v1/cms/categories/<slug>/pages?…` (same filters) for any
    category, not just blog home.
- Alembic migration `20260420_cms_category_blog_home.py`.
- Unit tests in `plugins/cms/tests/`.

### Frontend (plugin `vbwd-fe-user-plugin-cms`)
- Routes:
  - `/blog` → `BlogHome.vue` (paged list, search box, archive widget).
  - `/blog/archive/:month` → same component, month pre-filled.
  - `/blog/<category-slug>` → `BlogCategory.vue`.
- Pagination component reused across both.

### Frontend admin (plugin `vbwd-fe-admin-plugin-cms`)
- Toggle in `Categories.vue` detail: "Set as blog home".

## Out of scope
- RSS / Atom feeds (separate sprint).
- Comments.
- Per-post "featured image" uploads (can come later).

## Acceptance

1. Visiting `https://vbwd.cc/blog` after designating a blog-home category in
   the admin UI renders the expected list with working pagination.
2. A user without any designated blog-home sees a friendly empty-state on
   `/blog`, not a 500.
3. The admin UI has a single checkbox-like promote/demote UX; assigning a
   second category as blog home automatically demotes the previous one.
4. Sprint 24's `Blog` menu entry on main + each vertical resolves to 200.

## Effort estimate

~1 day for backend + migration + plugin UI. Worth a separate sprint because
it introduces a new public CMS endpoint surface and a domain-meaningful
schema flag.
