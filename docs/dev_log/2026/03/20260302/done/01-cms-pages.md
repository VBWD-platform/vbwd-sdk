# Sprint 01 — CMS Pages Plugin

**Date:** 2026-03-02
**Principles:** TDD-first · SOLID · DRY · Liskov · Dependency Injection · Clean Code
**Dependencies:** `theme-switcher` plugin (fe-user rendering)

---

## Overview

A full CMS system split across three components:
- **Backend plugin** — REST API, models, migrations
- **fe-admin plugin** — Pages, Categories, Image Gallery management
- **fe-user plugin** — Vue routes rendering pages to end users

---

## Architecture Decisions

| Concern | Decision |
|---|---|
| Page rendering | Vue SPA routes in fe-user (`/page/<slug>`) |
| Rich text editor | TipTap (ProseMirror-based) |
| Image storage | Local filesystem, bind-mounted to host (`/loopai_storage/vbwd/uploads/`) |
| Image reference in content | Direct URL path (`/uploads/images/my-image.jpg`) |
| Video | External embed (YouTube/Vimeo iframe) + local upload to same volume |
| Multilingual | One language per page — separate page records per language |
| URL structure | Flat — `/page/<slug>` |
| Categories | Navigation grouping + filterable in fe-user |
| SEO | Full — meta, OpenGraph, robots, schema.org JSON-LD |
| Tariff plan gating | None |

---

## Backend Plugin

### Models & Migrations

#### `cms_page`
```
id              UUID PK
slug            VARCHAR(128) UNIQUE NOT NULL
name            VARCHAR(255) NOT NULL
language        VARCHAR(8) NOT NULL DEFAULT 'en'   -- ISO 639-1
content_json    JSONB NOT NULL                      -- TipTap document JSON
category_id     UUID FK → cms_category (nullable)
is_published    BOOLEAN DEFAULT FALSE
sort_order      INT DEFAULT 0

-- SEO
meta_title          VARCHAR(255)
meta_description    TEXT
meta_keywords       TEXT
og_title            VARCHAR(255)
og_description      TEXT
og_image_url        VARCHAR(512)
canonical_url       VARCHAR(512)
robots              VARCHAR(64) DEFAULT 'index,follow'
schema_json         JSONB

created_at      TIMESTAMP
updated_at      TIMESTAMP
```

#### `cms_category`
```
id          UUID PK
slug        VARCHAR(128) UNIQUE NOT NULL
name        VARCHAR(255) NOT NULL
parent_id   UUID FK → cms_category (nullable, for nesting)
sort_order  INT DEFAULT 0
created_at  TIMESTAMP
updated_at  TIMESTAMP
```

#### `cms_image`
```
id              UUID PK
slug            VARCHAR(128) UNIQUE NOT NULL
caption         VARCHAR(255)
file_path       VARCHAR(512) NOT NULL   -- relative to uploads root
url_path        VARCHAR(512) NOT NULL   -- e.g. /uploads/images/foo.jpg
mime_type       VARCHAR(64)             -- image/png, image/jpeg, video/mp4
file_size_bytes INT
width_px        INT
height_px       INT

-- SEO
alt_text        VARCHAR(255)
og_image_url    VARCHAR(512)
robots          VARCHAR(64)
schema_json     JSONB

created_at  TIMESTAMP
updated_at  TIMESTAMP
```

---

### Repository Layer (DI-injected, interface-based)

```
ICmsPageRepository
  find_by_slug(slug) → CmsPage
  find_all(page, per_page, sort_by, filters) → PaginatedResult
  save(page) → CmsPage
  delete(id) → None
  bulk_publish(ids, published) → int
  bulk_delete(ids) → int
  bulk_set_category(ids, category_id) → int

ICmsCategoryRepository
  find_all() → List[CmsCategory]
  find_by_slug(slug) → CmsCategory
  save(cat) → CmsCategory
  delete(id) → None

ICmsImageRepository
  find_all(page, per_page, sort_by, query) → PaginatedResult
  find_by_id(id) → CmsImage
  save(image) → CmsImage
  delete(id) → None
  bulk_delete(ids) → None
```

---

### Service Layer

```
CmsPageService(repo: ICmsPageRepository, category_repo: ICmsCategoryRepository)
  get_page(slug) → CmsPageDTO
  list_pages(params) → PaginatedResult[CmsPageDTO]
  create_page(data) → CmsPageDTO
  update_page(id, data) → CmsPageDTO
  delete_page(id) → None
  bulk_action(ids, action, params) → BulkResult
  export_pages(ids, format) → bytes        -- json or json+base64images

CmsCategoryService(repo: ICmsCategoryRepository)
  list_categories() → List[CmsCategoryDTO]
  create_category(data) → CmsCategoryDTO
  update_category(id, data) → CmsCategoryDTO
  delete_category(id) → None

CmsImageService(repo: ICmsImageRepository, storage: IFileStorage)
  list_images(params) → PaginatedResult[CmsImageDTO]
  upload_image(file) → CmsImageDTO
  update_image(id, data) → CmsImageDTO
  resize_image(id, width, height) → CmsImageDTO
  delete_image(id) → None
  bulk_delete(ids) → None
  export_zip(ids) → bytes

IFileStorage                               -- DI interface
  save(file, path) → str
  delete(path) → None
  get_url(path) → str

LocalFileStorage(IFileStorage)             -- bind-mount implementation
  base_path: /loopai_storage/vbwd/uploads
  base_url:  /uploads
```

---

### API Endpoints

```
# Pages
GET    /api/v1/admin/cms/pages              list (paginated, sortable, filterable)
POST   /api/v1/admin/cms/pages              create
GET    /api/v1/admin/cms/pages/<id>         get
PUT    /api/v1/admin/cms/pages/<id>         update
DELETE /api/v1/admin/cms/pages/<id>         delete
POST   /api/v1/admin/cms/pages/bulk         bulk action (publish/unpublish/delete/set-category)
POST   /api/v1/admin/cms/pages/export       export selected (json or json+base64)
POST   /api/v1/admin/cms/pages/import       import

# Public (fe-user)
GET    /api/v1/cms/pages/<slug>             get published page by slug
GET    /api/v1/cms/pages?category=<slug>    list published pages by category

# Categories
GET    /api/v1/admin/cms/categories         list
POST   /api/v1/admin/cms/categories         create
PUT    /api/v1/admin/cms/categories/<id>    update
DELETE /api/v1/admin/cms/categories/<id>    delete

# Images
GET    /api/v1/admin/cms/images             list (paginated, sortable, quicksearch)
POST   /api/v1/admin/cms/images/upload      upload (multipart)
PUT    /api/v1/admin/cms/images/<id>        update caption/SEO
POST   /api/v1/admin/cms/images/<id>/resize resize
DELETE /api/v1/admin/cms/images/<id>        delete
POST   /api/v1/admin/cms/images/bulk        bulk delete
GET    /api/v1/admin/cms/images/export      export zip
```

---

### Tests (TDD — write first)

```
tests/unit/services/
  test_cms_page_service.py
    - test_get_page_by_slug_returns_dto
    - test_get_unpublished_page_raises_not_found
    - test_create_page_validates_slug_uniqueness
    - test_bulk_publish_updates_all_ids
    - test_export_json_includes_all_fields
    - test_export_base64_encodes_images

  test_cms_category_service.py
    - test_create_category_slug_auto_generated
    - test_delete_category_with_pages_raises_conflict

  test_cms_image_service.py
    - test_upload_saves_to_storage_and_persists_record
    - test_resize_updates_dimensions
    - test_bulk_delete_removes_files_and_records
    - test_export_zip_contains_all_selected_files

tests/unit/repositories/
  test_cms_page_repository.py
  test_cms_image_repository.py

tests/integration/
  test_cms_pages_api.py
  test_cms_images_api.py
```

---

## fe-admin Plugin

### Routes

```
/admin/cms/pages              CmsPageList.vue
/admin/cms/pages/new          CmsPageEditor.vue
/admin/cms/pages/:id/edit     CmsPageEditor.vue
/admin/cms/categories         CmsCategoryList.vue
/admin/cms/images             CmsImageGallery.vue
/admin/cms/images/:id/edit    CmsImageEditor.vue
```

### Components

```
CmsPageList.vue
  - Sortable columns: name, slug, language, category, published, updated_at
  - Checkbox column → bulk action toolbar
  - Bulk actions: publish, unpublish, set category, delete, export
  - Pagination + per-page selector

CmsPageEditor.vue
  - TipTap editor with toolbar:
      bold, italic, headings, lists, blockquote
      image picker (opens CmsImagePicker)
      video embed (URL input → iframe) + video upload
      html snippet block, js snippet block
  - Sidebar: name, slug (auto-generated, editable), language, category, published toggle
  - SEO tab: meta_title, meta_description, meta_keywords,
             og_title, og_description, og_image, canonical_url,
             robots (select), schema_json (textarea)
  - Save / Save & Preview buttons

CmsImagePicker.vue              -- shared modal, used by editor
  - Grid/list toggle
  - Quicksearch, pagination
  - Click to select → inserts /uploads/... URL into editor

CmsCategoryList.vue
  - Name, slug, parent, sort_order columns
  - Inline edit, drag-to-reorder sort_order
  - Add/delete

CmsImageGallery.vue
  - Grid/list toggle view
  - Sortable: caption, slug, type, size, created_at
  - Quicksearch
  - Bulk: delete, export zip
  - Upload button (drag & drop + file picker)
  - Click row → CmsImageEditor

CmsImageEditor.vue
  - Visual resize (drag handles + numeric inputs)
  - Caption, alt_text, slug
  - SEO fields: og_image_url, robots, schema_json
  - Delete button
```

### Store (`useCmsStore`)

```typescript
// Pinia store — DI via composables
state: {
  pages: PaginatedResult<CmsPage>
  currentPage: CmsPage | null
  categories: CmsCategory[]
  images: PaginatedResult<CmsImage>
  currentImage: CmsImage | null
  loading: boolean
  error: string | null
}
actions:
  fetchPages(params)
  fetchPage(id)
  savePage(data)
  deletePage(id)
  bulkAction(ids, action, params)
  fetchCategories()
  saveCategory(data)
  deleteCategory(id)
  fetchImages(params)
  uploadImage(file)
  saveImage(id, data)
  resizeImage(id, w, h)
  deleteImage(id)
  exportImagesZip(ids)
```

---

## fe-user Plugin

### Routes

```
/page/:slug       CmsPage.vue     -- renders published page by slug
/pages            CmsPageIndex.vue -- lists pages, filterable by category
```

### Components

```
CmsPage.vue
  - Fetches page by slug from /api/v1/cms/pages/:slug
  - Renders TipTap JSON content as HTML
  - Injects SEO meta tags into <head> (meta, og:*, robots, schema.org)
  - Theme-switcher compliant (wraps in theme slot)
  - 404 if page not found or unpublished

CmsPageIndex.vue
  - Category filter tabs (from /api/v1/cms/categories)
  - Paginated list of published pages
  - Links to /page/:slug
```

---

## docker-compose.server.yaml — volume addition

```yaml
vbwd_backend:
  volumes:
    - /loopai_storage/vbwd/uploads:/app/uploads

vbwd_fe_user:
  volumes:
    - /loopai_storage/vbwd/uploads:/usr/share/nginx/html/uploads:ro

vbwd_fe_admin:
  volumes:
    - /loopai_storage/vbwd/uploads:/usr/share/nginx/html/uploads:ro
```

---

## Implementation Order (TDD)

```
1. Write failing tests for CmsPageService
2. Implement models + migration
3. Implement LocalFileStorage
4. Implement repositories
5. Implement services (tests go green)
6. Implement API endpoints + integration tests
7. fe-admin: CmsImageGallery + upload flow
8. fe-admin: CmsPageEditor + TipTap integration
9. fe-admin: CmsPageList + bulk ops
10. fe-admin: CmsCategoryList
11. fe-user: CmsPage.vue + SEO injection
12. fe-user: CmsPageIndex.vue + category filter
13. E2E: create page → publish → view in fe-user
```
