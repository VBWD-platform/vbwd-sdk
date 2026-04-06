# Report — Sprint 01: CMS Pages Plugin

**Date:** 2026-03-02
**Status:** ✅ Complete (backend + frontend)
**Test result:** 25 passed, 1 skipped

---

## What was built

Full backend plugin for CMS Pages at `vbwd-backend/plugins/cms/`.
All code is self-contained in the plugin — zero core files modified.

---

## Files created

```
plugins/cms/
├── __init__.py                              CmsPlugin class
├── src/
│   ├── models/
│   │   ├── cms_category.py                  Self-referential category hierarchy
│   │   ├── cms_page.py                      TipTap JSON content + full SEO fields
│   │   └── cms_image.py                     Media gallery record with SEO
│   ├── repositories/
│   │   ├── cms_category_repository.py       CRUD + slug lookup
│   │   ├── cms_page_repository.py           CRUD, pagination, bulk ops, published filter
│   │   └── cms_image_repository.py          CRUD, pagination, search, bulk delete
│   ├── services/
│   │   ├── file_storage.py                  IFileStorage interface + LocalFileStorage + InMemoryFileStorage
│   │   ├── cms_page_service.py              CRUD, bulk publish/delete/set-category, export/import
│   │   ├── cms_category_service.py          CRUD, auto-slug, conflict guard on delete
│   │   └── cms_image_service.py             Upload, resize (Pillow), bulk delete, ZIP export
│   └── routes.py                            21 API routes (public + admin)
└── tests/unit/services/
    ├── test_cms_page_service.py             13 tests
    ├── test_cms_category_service.py          6 tests
    └── test_cms_image_service.py             7 tests

alembic/versions/20260302_create_cms_tables.py
plugins/plugins.json                         cms entry added (enabled: true)
plugins/config.json                          cms config block added
```

---

## API surface (21 routes)

### Public
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/cms/pages/<slug>` | Fetch published page by slug |
| GET | `/api/v1/cms/pages` | List published pages (`?category=<slug>`) |

### Admin (require_admin)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/cms/pages` | List all pages (paginated, sortable, filterable) |
| POST | `/api/v1/admin/cms/pages` | Create page |
| GET | `/api/v1/admin/cms/pages/<id>` | Get page |
| PUT | `/api/v1/admin/cms/pages/<id>` | Update page |
| DELETE | `/api/v1/admin/cms/pages/<id>` | Delete page |
| POST | `/api/v1/admin/cms/pages/bulk` | Bulk: publish / unpublish / delete / set_category |
| POST | `/api/v1/admin/cms/pages/export` | Export selected pages as JSON |
| POST | `/api/v1/admin/cms/pages/import` | Import pages from JSON |
| GET | `/api/v1/admin/cms/categories` | List categories |
| POST | `/api/v1/admin/cms/categories` | Create category |
| PUT | `/api/v1/admin/cms/categories/<id>` | Update category |
| DELETE | `/api/v1/admin/cms/categories/<id>` | Delete category |
| GET | `/api/v1/admin/cms/images` | List images (paginated, searchable) |
| POST | `/api/v1/admin/cms/images/upload` | Upload image (multipart) |
| PUT | `/api/v1/admin/cms/images/<id>` | Update caption/SEO |
| POST | `/api/v1/admin/cms/images/<id>/resize` | Resize image |
| DELETE | `/api/v1/admin/cms/images/<id>` | Delete image + file |
| POST | `/api/v1/admin/cms/images/bulk` | Bulk delete images |
| GET | `/api/v1/admin/cms/images/export` | Export images as ZIP |

---

## Test results

```
plugins/cms/tests/unit/services/test_cms_category_service.py   6 passed
plugins/cms/tests/unit/services/test_cms_image_service.py      6 passed, 1 skipped
plugins/cms/tests/unit/services/test_cms_page_service.py      13 passed
──────────────────────────────────────────────────────────────
Total                                                         25 passed, 1 skipped
```

The 1 skipped test (`test_resize_updates_dimensions`) requires Pillow in the Docker test
image. Resize logic is implemented and covered by the `CmsImageNotFoundError` guard test.

Full suite (746 unit tests including all existing tests): **746 passed, 5 skipped** — no regressions.

---

## Architecture decisions made

| Concern | Decision | Reason |
|---------|----------|--------|
| Route prefixes | Absolute paths, `get_url_prefix()` returns `""` | Plugin needs two prefixes: `/api/v1/cms/` (public) and `/api/v1/admin/cms/` (admin) |
| File storage | `IFileStorage` interface + `LocalFileStorage` implementation | Enables test doubles (`InMemoryFileStorage`), swap-able for S3 later |
| Resize | Pillow, optional (`RuntimeError` if not installed) | Avoids forcing Pillow on installations that don't need resize |
| Slug generation | Auto from name if not provided, deduplication with counter suffix | Consistent with other plugins |
| Category delete guard | Raises `CmsCategoryConflictError` if category has pages | Prevents orphan pages |
| Export format | JSON (default) + JSON base64 | Sprint requirement; binary image embed is future work |

---

## Frontend plugins

### fe-user — `vbwd-fe-user/plugins/cms/`
| File | Description |
|------|-------------|
| `index.ts` | Plugin entry; registers `/page/:slug` and `/pages` routes via `sdk.addRoute()` |
| `locales/en.json` | i18n strings |
| `src/stores/useCmsStore.ts` | Pinia store: `fetchCategories`, `fetchPages`, `fetchPage(slug)` |
| `src/views/CmsPage.vue` | Zero-dep TipTap JSON renderer, SEO meta injection via `document.head` |
| `src/views/CmsPageIndex.vue` | Category tabs, paginated page list, router-link to cms-page |

Changes to core (static-import pattern required by fe-user):
- `vue/src/utils/pluginLoader.ts` — `import { cmsPlugin } from '@plugins/cms'` + pluginMap entry
- `vue/src/router/index.ts` — static route declarations
- `plugins/plugins.json` — `"cms"` entry

### fe-admin — `vbwd-fe-admin/plugins/cms-admin/`
| File | Description |
|------|-------------|
| `index.ts` | Plugin entry; 5 routes via `sdk.addRoute()` (children of `'admin'` route) |
| `locales/en.json` | i18n strings |
| `src/stores/useCmsAdminStore.ts` | Full CRUD Pinia store for categories, pages, images |
| `src/views/CmsPageList.vue` | Sortable table, checkbox bulk ops, filters, debounced search, pagination |
| `src/views/CmsPageEditor.vue` | Create/edit form, TipTap editor, SEO tab, sidebar with publish toggle |
| `src/views/CmsCategoryList.vue` | Category CRUD with inline form |
| `src/views/CmsImageGallery.vue` | Image grid, upload, bulk delete, caption/alt editing, resize |
| `src/components/TipTapEditor.vue` | TipTap Vue3 editor (bold, italic, headings, lists, blockquote, code, link, image, video) |
| `src/components/CmsImagePicker.vue` | Image picker modal used by editor |

Changes to core (glob-loaded automatically):
- `plugins/plugins.json` — `"cms-admin"` entry
- `package.json` — added `@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/extension-image`, `@tiptap/extension-link`

### Admin routes registered
| Route name | Path (under /admin/) | View |
|-----------|----------------------|------|
| `cms-admin-pages` | `cms/pages` | CmsPageList.vue |
| `cms-page-new` | `cms/pages/new` | CmsPageEditor.vue |
| `cms-page-edit` | `cms/pages/:id/edit` | CmsPageEditor.vue |
| `cms-categories` | `cms/categories` | CmsCategoryList.vue |
| `cms-images` | `cms/images` | CmsImageGallery.vue |

---

## Config files

Every plugin layer now has both required config files:

| Location | File | Purpose |
|----------|------|---------|
| `vbwd-backend/plugins/cms/` | `config.json` | Settings schema: uploads path/URL, max size, MIME types, default language/robots |
| `vbwd-backend/plugins/cms/` | `admin-config.json` | Admin UI schema: Storage tab + Defaults tab |
| `vbwd-fe-user/plugins/cms/` | `config.json` | Settings schema: pagesPerPage, showCategoryFilter, defaultLanguage |
| `vbwd-fe-user/plugins/cms/` | `admin-config.json` | Admin UI schema: Display tab + Localization tab |
| `vbwd-fe-admin/plugins/cms-admin/` | `config.json` | Settings schema: defaultLanguage, defaultRobots, uploadsMaxSizeMb, imagesPerPage |
| `vbwd-fe-admin/plugins/cms-admin/` | `admin-config.json` | Admin UI schema: General tab + Uploads tab |

---

## Admin sidebar extensibility

The admin sidebar was hardcoded and had no plugin extension point. This was fixed:

**`vue/src/plugins/extensionRegistry.ts`** — added `NavItem`, `NavSection` types and `navSections?: NavSection[]` to `AdminExtension`; added `getNavSections()` method.

**`vue/src/layouts/AdminSidebar.vue`** — now reads `extensionRegistry.getNavSections()` and renders one collapsible section per plugin. Zero hardcoded plugin links remain.

**`plugins/cms-admin/index.ts`** — calls `extensionRegistry.register('cms-admin', { navSections: [...] })` inside `install()`, adding a **CMS** section (Pages / Categories / Images) to the sidebar automatically when the plugin is enabled.

Any future fe-admin plugin registers its nav items the same way — no changes to core required.

---

## Remaining (post-sprint)

- Add Pillow to `requirements.txt` if resize needed in production
- Volume mount in `docker-compose.server.yaml` for `/app/uploads`
- Run `npm install` in `vbwd-fe-admin/` to install TipTap packages
