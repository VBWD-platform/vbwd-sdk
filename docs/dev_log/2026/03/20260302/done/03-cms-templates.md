# Sprint 03 — CMS Templates: Layouts, Widgets, Menus & Styles

**Date:** 2026-03-05
**Principles:** TDD-first · SOLID · DRY · Liskov · Dependency Injection · Clean Code
**Dependencies:** `cms` plugin (Sprint 01), `theme-switcher` plugin (fe-user rendering)

---

## Overview

Extends the existing `cms` backend plugin and fe-admin/fe-user plugins with:

- **Layouts** — Named page structure templates composed from a fixed catalogue of area types
- **Widgets** — Reusable content blocks (html, menu, slideshow) assigned to layout areas
- **Styles** — Plain CSS stylesheets assignable to pages/layouts, optionally overriding theme-switcher
- **WYSIWYG HTML tab** — Two-way sync raw HTML view added to TipTap editor (pages and html widgets)
- **Import/Export** — JSON (single item) and ZIP+base64 (bulk) for layouts, widgets, styles; slug collision → auto-rename with suffix

No new plugins created — all code lives inside the existing `plugins/cms/` backend plugin and the existing fe-admin/fe-user CMS plugins.

---

## Architecture Decisions

| Concern | Decision |
|---|---|
| Widget-area assignment | Layout-level only — all pages sharing a layout share the same widgets |
| Area types | Fixed catalogue (8 types) — admin composes layouts by picking from list |
| `content` area | Optional — layouts can omit it (pure widget compositions, e.g. landing page) |
| Menu | Widget type (`type=menu`) — not a separate entity; tree builder is the menu widget editor |
| CSS | Plain CSS only — no LESS/SCSS compilation |
| WYSIWYG HTML tab | Two-way sync — edit raw HTML → TipTap re-parses on tab switch |
| Slug collision on import | Auto-rename with suffix (e.g. `my-layout-2`) |
| Core files | No modifications to `src/` — all code in `plugins/cms/` |

---

## Fixed Area Type Catalogue

| Type | Description | Widget required |
|---|---|---|
| `header` | Top navigation / page header bar | yes |
| `footer` | Page footer bar | yes |
| `hero` | Full-width hero/banner area | yes |
| `slideshow` | Image carousel | yes |
| `content` | Main page content body (renders `cms_page.content_json`) | **no** |
| `three-column` | Three equal columns — up to 3 widgets by `sort_order` | yes |
| `two-column` | Two columns — up to 2 widgets by `sort_order` | yes |
| `cta-bar` | Call-to-action bar | yes |

`content` areas never have a widget assignment — they render the page's own TipTap content.
All other area types render the widget(s) assigned to that area in `cms_layout_widget`.

## Widget Type Catalogue

| Type | Editor UI | Config shape |
|---|---|---|
| `html` | TipTap WYSIWYG + HTML tab | `content_json` (TipTap) + `content_html` (raw) |
| `menu` | Multilevel tree builder | `cms_menu_item` child rows |
| `slideshow` | Image list referencing `cms_image` IDs | `config.images: [{image_id, caption, link_url}]` |

---

## Backend Plugin — Models & Migrations

All new tables added to the existing `plugins/cms/` migration.

### `cms_layout`

```
id              UUID PK
slug            VARCHAR(128) UNIQUE NOT NULL
name            VARCHAR(255) NOT NULL
description     TEXT
areas           JSONB NOT NULL   -- ordered list of area definitions (see below)
sort_order      INT DEFAULT 0
is_active       BOOLEAN DEFAULT TRUE
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

`areas` JSONB shape:
```json
[
  {"name": "page-header", "type": "header",    "label": "Page Header"},
  {"name": "hero-slider", "type": "slideshow", "label": "Hero Slideshow"},
  {"name": "main-body",   "type": "content",   "label": "Main Content"},
  {"name": "page-footer", "type": "footer",    "label": "Page Footer"}
]
```
`name` is the unique key used in `cms_layout_widget.area_name`.
`type` must be one of the 8 fixed area types.

---

### `cms_layout_widget`

```
id              UUID PK
layout_id       UUID FK → cms_layout NOT NULL
widget_id       UUID FK → cms_widget NOT NULL
area_name       VARCHAR(64) NOT NULL   -- references an area name from cms_layout.areas
sort_order      INT DEFAULT 0          -- position within the area (for multi-widget areas)
created_at      TIMESTAMP

UNIQUE(layout_id, widget_id, area_name)
```

---

### `cms_widget`

```
id              UUID PK
slug            VARCHAR(128) UNIQUE NOT NULL
name            VARCHAR(255) NOT NULL
widget_type     VARCHAR(32) NOT NULL   -- html | menu | slideshow
content_json    JSONB                  -- TipTap document (type=html)
content_html    TEXT                   -- raw HTML mirror (type=html, two-way sync)
config          JSONB                  -- type-specific config (type=slideshow: image list)
sort_order      INT DEFAULT 0
is_active       BOOLEAN DEFAULT TRUE
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

---

### `cms_menu_item`

```
id              UUID PK
widget_id       UUID FK → cms_widget NOT NULL   -- the menu widget this item belongs to
parent_id       UUID FK → cms_menu_item          -- nullable, for nesting
label           VARCHAR(255) NOT NULL
url             VARCHAR(512)                      -- nullable, external URL
page_slug       VARCHAR(128)                      -- nullable, links to cms_page by slug
target          VARCHAR(16) DEFAULT '_self'
icon            VARCHAR(64)                       -- nullable, icon class or name
sort_order      INT DEFAULT 0
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

---

### `cms_style`

```
id              UUID PK
slug            VARCHAR(128) UNIQUE NOT NULL
name            VARCHAR(255) NOT NULL
source_css      TEXT NOT NULL
sort_order      INT DEFAULT 0
is_active       BOOLEAN DEFAULT TRUE
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

---

### `cms_page` — extended columns

```
layout_id              UUID FK → cms_layout (nullable — no layout = plain content only)
style_id               UUID FK → cms_style  (nullable — override page style)
use_theme_switcher_styles  BOOLEAN DEFAULT TRUE
```

---

## Backend Plugin — Repository Layer

### New interfaces

```
ICmsLayoutRepository
  find_all(page, per_page, sort_by, query) → PaginatedResult
  find_by_id(id) → CmsLayout
  find_by_slug(slug) → CmsLayout
  save(layout) → CmsLayout
  delete(id) → None
  bulk_delete(ids) → int

ICmsLayoutWidgetRepository
  find_by_layout(layout_id) → List[CmsLayoutWidget]
  replace_for_layout(layout_id, assignments) → List[CmsLayoutWidget]
  delete_by_layout(layout_id) → None

ICmsWidgetRepository
  find_all(page, per_page, sort_by, query, widget_type) → PaginatedResult
  find_by_id(id) → CmsWidget
  find_by_slug(slug) → CmsWidget
  save(widget) → CmsWidget
  delete(id) → None
  bulk_delete(ids) → int

ICmsMenuItemRepository
  find_tree_by_widget(widget_id) → List[CmsMenuItem]   -- returns flat list, ordered
  replace_tree(widget_id, items) → List[CmsMenuItem]   -- replace entire tree atomically
  delete_by_widget(widget_id) → None

ICmsStyleRepository
  find_all(page, per_page, sort_by, query) → PaginatedResult
  find_by_id(id) → CmsStyle
  find_by_slug(slug) → CmsStyle
  save(style) → CmsStyle
  delete(id) → None
  bulk_delete(ids) → int
```

---

## Backend Plugin — Service Layer

```
CmsLayoutService(
    layout_repo: ICmsLayoutRepository,
    layout_widget_repo: ICmsLayoutWidgetRepository,
    widget_repo: ICmsWidgetRepository
)
  list_layouts(params) → PaginatedResult[CmsLayoutDTO]
  get_layout(id) → CmsLayoutDTO           -- includes area definitions + widget assignments
  create_layout(data) → CmsLayoutDTO
  update_layout(id, data) → CmsLayoutDTO
  delete_layout(id) → None
  bulk_delete(ids) → int
  set_widget_assignments(layout_id, assignments) → List[CmsLayoutWidgetDTO]
  export_layout(id) → dict               -- JSON-serialisable dict (single)
  export_layouts_zip(ids) → bytes        -- ZIP with base64 images
  import_layout(data) → CmsLayoutDTO    -- handles slug collision → suffix rename


CmsWidgetService(
    widget_repo: ICmsWidgetRepository,
    menu_item_repo: ICmsMenuItemRepository,
    image_repo: ICmsImageRepository
)
  list_widgets(params) → PaginatedResult[CmsWidgetDTO]
  get_widget(id) → CmsWidgetDTO          -- includes menu tree if type=menu
  create_widget(data) → CmsWidgetDTO
  update_widget(id, data) → CmsWidgetDTO
  delete_widget(id) → None
  bulk_delete(ids) → int
  replace_menu_tree(widget_id, items) → List[CmsMenuItemDTO]
  export_widget(id) → dict
  export_widgets_zip(ids) → bytes
  import_widget(data) → CmsWidgetDTO    -- slug collision → suffix rename


CmsStyleService(
    style_repo: ICmsStyleRepository
)
  list_styles(params) → PaginatedResult[CmsStyleDTO]
  get_style(id) → CmsStyleDTO
  get_style_css(id) → str               -- returns source_css for public serving
  create_style(data) → CmsStyleDTO
  update_style(id, data) → CmsStyleDTO
  delete_style(id) → None
  bulk_delete(ids) → int
  export_style(id) → dict
  export_styles_zip(ids) → bytes
  import_style(data) → CmsStyleDTO     -- slug collision → suffix rename
```

### Slug collision helper (shared, DRY)

```python
# plugins/cms/src/services/_slug.py
def unique_slug(slug: str, exists_fn: Callable[[str], bool]) -> str:
    """Appends -2, -3, ... until slug is unique."""
```

---

## Backend Plugin — API Endpoints

### Layouts (admin)

```
GET    /api/v1/admin/cms/layouts                list (paginated, sortable, quicksearch)
POST   /api/v1/admin/cms/layouts                create
GET    /api/v1/admin/cms/layouts/<id>           get (includes widget assignments)
PUT    /api/v1/admin/cms/layouts/<id>           update areas + metadata
DELETE /api/v1/admin/cms/layouts/<id>           delete
POST   /api/v1/admin/cms/layouts/bulk           bulk delete
PUT    /api/v1/admin/cms/layouts/<id>/widgets   replace all widget assignments for layout
POST   /api/v1/admin/cms/layouts/export         export selected → single JSON or ZIP
POST   /api/v1/admin/cms/layouts/import         import from JSON or ZIP
```

### Widgets (admin)

```
GET    /api/v1/admin/cms/widgets                list (paginated, sortable, quicksearch, ?type=)
POST   /api/v1/admin/cms/widgets                create
GET    /api/v1/admin/cms/widgets/<id>           get (includes menu tree if type=menu)
PUT    /api/v1/admin/cms/widgets/<id>           update
DELETE /api/v1/admin/cms/widgets/<id>           delete
POST   /api/v1/admin/cms/widgets/bulk           bulk delete
PUT    /api/v1/admin/cms/widgets/<id>/menu      replace entire menu item tree
POST   /api/v1/admin/cms/widgets/export         export selected → single JSON or ZIP
POST   /api/v1/admin/cms/widgets/import         import
```

### Styles (admin)

```
GET    /api/v1/admin/cms/styles                 list (paginated, sortable, quicksearch)
POST   /api/v1/admin/cms/styles                 create
GET    /api/v1/admin/cms/styles/<id>            get
PUT    /api/v1/admin/cms/styles/<id>            update
DELETE /api/v1/admin/cms/styles/<id>            delete
POST   /api/v1/admin/cms/styles/bulk            bulk delete
POST   /api/v1/admin/cms/styles/export          export selected → single JSON or ZIP
POST   /api/v1/admin/cms/styles/import          import
```

### Public (fe-user)

```
GET    /api/v1/cms/layouts/<id>                 get layout with widget assignments (rendered by fe-user)
GET    /api/v1/cms/styles/<id>/css              serve style as text/css
```

### Pages (extended)

Existing page endpoints extended: `layout_id`, `style_id`, `use_theme_switcher_styles` added to create/update payloads and response DTOs.

---

## Backend Plugin — Tests (TDD — write first)

```
plugins/cms/tests/unit/services/
  test_cms_layout_service.py
    - test_create_layout_validates_area_types
    - test_create_layout_rejects_unknown_area_type
    - test_set_widget_assignments_replaces_atomically
    - test_content_area_cannot_have_widget_assigned
    - test_delete_layout_unlinks_pages_layout_id
    - test_export_layout_json_includes_widget_slugs
    - test_import_layout_renames_slug_on_collision

  test_cms_widget_service.py
    - test_create_widget_html_stores_content_json
    - test_update_widget_html_syncs_content_html
    - test_replace_menu_tree_atomically
    - test_delete_widget_used_in_layout_raises_conflict
    - test_export_widget_slideshow_encodes_images_base64
    - test_import_widget_renames_slug_on_collision

  test_cms_style_service.py
    - test_create_style_stores_source_css
    - test_get_style_css_returns_source
    - test_import_style_renames_slug_on_collision
    - test_bulk_delete_removes_all

plugins/cms/tests/integration/
  test_cms_layouts_api.py
  test_cms_widgets_api.py
  test_cms_styles_api.py
  test_cms_page_layout_api.py   -- pages with layout_id + style_id
```

---

## fe-admin Plugin

### New routes

```
/admin/cms/layouts                   CmsLayoutList.vue
/admin/cms/layouts/new               CmsLayoutEditor.vue
/admin/cms/layouts/:id/edit          CmsLayoutEditor.vue
/admin/cms/widgets                   CmsWidgetList.vue
/admin/cms/widgets/new               CmsWidgetEditor.vue
/admin/cms/widgets/:id/edit          CmsWidgetEditor.vue
/admin/cms/styles                    CmsStyleList.vue
/admin/cms/styles/new                CmsStyleEditor.vue
/admin/cms/styles/:id/edit           CmsStyleEditor.vue
```

Existing route `/admin/cms/pages/:id/edit` — `CmsPageEditor.vue` extended with layout + style selectors.

### CMS dashboard sidebar — new sub-items under CMS

```
CMS
  Pages       (existing)
  Categories  (existing)
  Images      (existing)
  Layouts     (new)
  Widgets     (new)
  Styles      (new)
```

---

### Components

#### `CmsLayoutList.vue`
- Sortable columns: name, slug, areas (count), active, updated_at
- Checkbox column → bulk delete toolbar
- Pagination + per-page + quicksearch
- Export selected (JSON single / ZIP bulk)
- Import button (JSON or ZIP)
- Row click → CmsLayoutEditor

#### `CmsLayoutEditor.vue`
- Fields: name, slug (auto + editable), description, is_active
- Area builder:
  - Ordered list of areas (drag to reorder)
  - Add area: pick type from fixed catalogue dropdown, enter label + name
  - Cannot add duplicate area names
  - `content` type area has no widget picker (labelled "Page content body")
  - All other area types show widget picker → opens `CmsWidgetPicker` modal
  - Multi-widget areas (three-column, two-column): shows up to N widget slots with order handles
- Save button

#### `CmsWidgetList.vue`
- Sortable columns: name, slug, type, active, updated_at
- Filter by widget type
- Checkbox column → bulk delete toolbar
- Pagination + per-page + quicksearch
- Export / Import buttons
- Row click → CmsWidgetEditor

#### `CmsWidgetEditor.vue`
- Fields: name, slug (auto + editable), is_active
- `widget_type` selector (html / menu / slideshow) — locked after first save
- Editor panel switches by type:
  - **type=html**: TipTap toolbar + **HTML tab** (see below)
  - **type=menu**: `CmsMenuTreeEditor` (see below)
  - **type=slideshow**: image list — each row has image picker (opens `CmsImagePicker`), caption, link_url; drag to reorder
- Save button

#### TipTap HTML Tab (shared — used in `CmsWidgetEditor` and `CmsPageEditor`)
- Two tabs: "Visual" | "HTML"
- Switch to HTML: `generateHTML(doc, extensions)` → render into `<textarea>`
- Switch to Visual: parse textarea value → `generateJSON(html, extensions)` → load into TipTap
- Both `content_json` and `content_html` sent to backend on save
- Warn toast on tab switch if HTML parse produces empty doc

#### `CmsMenuTreeEditor.vue`
- Tree view of menu items (nested, drag-to-reorder within level)
- Each item: label, URL or page_slug picker, target, icon
- Add child button per item; max depth: 3 levels
- Delete item (with children)
- Save tree → `PUT /api/v1/admin/cms/widgets/:id/menu`

#### `CmsWidgetPicker.vue` (modal)
- List of widgets, filterable by type and quicksearch
- Click to select → returns widget id + name to caller

#### `CmsStyleList.vue`
- Sortable columns: name, slug, active, updated_at
- Checkbox column → bulk delete toolbar
- Pagination + per-page + quicksearch
- Export / Import buttons
- Row click → CmsStyleEditor

#### `CmsStyleEditor.vue`
- Fields: name, slug (auto + editable), is_active
- CSS editor: `<textarea>` with monospace font (plain CSS, no compilation)
- Live preview panel: injects CSS into a scoped `<style>` tag in a sandboxed preview iframe
- Save button

#### `CmsPageEditor.vue` — extensions
- New sidebar section "Layout & Style":
  - Layout selector (searchable dropdown → `GET /api/v1/admin/cms/layouts`)
  - Style selector (searchable dropdown → `GET /api/v1/admin/cms/styles`) + "Use theme-switcher styles" toggle
  - If style selected and `use_theme_switcher_styles = false`: warning "This page will override the global theme"
- HTML tab added to existing TipTap editor

---

### Store extensions (`useCmsStore`)

```typescript
// Added to existing useCmsStore

// Layouts
layouts: PaginatedResult<CmsLayout>
currentLayout: CmsLayout | null
fetchLayouts(params)
fetchLayout(id)
saveLayout(data)
deleteLayout(id)
setWidgetAssignments(layoutId, assignments)
bulkDeleteLayouts(ids)
exportLayouts(ids)
importLayouts(file)

// Widgets
widgets: PaginatedResult<CmsWidget>
currentWidget: CmsWidget | null
fetchWidgets(params)
fetchWidget(id)
saveWidget(data)
deleteWidget(id)
replaceMenuTree(widgetId, items)
bulkDeleteWidgets(ids)
exportWidgets(ids)
importWidgets(file)

// Styles
styles: PaginatedResult<CmsStyle>
currentStyle: CmsStyle | null
fetchStyles(params)
fetchStyle(id)
saveStyle(data)
deleteStyle(id)
bulkDeleteStyles(ids)
exportStyles(ids)
importStyles(file)
```

---

## fe-user Plugin

### `CmsPage.vue` — extended rendering

```
Fetch page: GET /api/v1/cms/pages/:slug
  → page has layout_id, style_id, use_theme_switcher_styles, content_json

IF style_id AND NOT use_theme_switcher_styles:
  GET /api/v1/cms/styles/:style_id/css
  Inject as <style> tag scoped to page wrapper

IF layout_id:
  GET /api/v1/cms/layouts/:layout_id
  → layout has ordered areas + widget assignments

  Render areas in order:
    area.type == 'content'   → render page content_json via TipTap HTML renderer
    area.type == 'header'    → <CmsAreaHeader :widget="widget" />
    area.type == 'footer'    → <CmsAreaFooter :widget="widget" />
    area.type == 'hero'      → <CmsAreaHero :widget="widget" />
    area.type == 'slideshow' → <CmsAreaSlideshow :widget="widget" />
    area.type == 'cta-bar'   → <CmsAreaCtaBar :widget="widget" />
    area.type == 'two-column'   → <CmsAreaTwoColumn :widgets="widgets" />
    area.type == 'three-column' → <CmsAreaThreeColumn :widgets="widgets" />

ELSE (no layout):
  Render content_json only (existing behaviour — backward compatible)
```

### New fe-user components

```
CmsAreaHeader.vue       -- renders html widget content in header structure
CmsAreaFooter.vue       -- renders html widget content in footer structure
CmsAreaHero.vue         -- full-width hero, renders html widget
CmsAreaSlideshow.vue    -- image carousel from widget.config.images
CmsAreaCtaBar.vue       -- renders html widget in full-width CTA bar
CmsAreaTwoColumn.vue    -- two-column flex/grid, renders up to 2 widgets
CmsAreaThreeColumn.vue  -- three-column grid, renders up to 3 widgets
CmsWidgetRenderer.vue   -- shared: given a widget, dispatches to correct renderer
CmsMenuWidget.vue       -- renders type=menu widget as burger/navbar from menu item tree
```

All components are theme-switcher compliant (use CSS variables from theme-switcher token set as defaults, overridable by page style).

### fe-user store extension (`useCmsStore`)

```typescript
currentLayout: CmsLayout | null
currentStyle: string | null    // raw CSS string
fetchLayout(id)
fetchStyleCss(id)
```

---

## Import / Export — Slug Collision Behaviour

Applies to layouts, widgets, and styles.

```
Single export → JSON file:
  { type: "cms_layout", version: 1, data: { ...layout, widget_slugs: [...] } }

Bulk export → ZIP file:
  layouts/my-layout.json
  widgets/my-widget.json
  images/abc123.jpg    ← base64-decoded from JSON on export
  manifest.json        ← { exported_at, counts: {layouts, widgets, images} }

Import single JSON:
  Parse → validate type field → check slug → if exists: append -2/-3/...
  → save → return created/renamed item

Import ZIP:
  Unzip → import images first (to resolve references) → import widgets → import layouts
  All slug collisions renamed with suffix
  Return import summary: { created, renamed, skipped_errors }
```

---

## Implementation Order (TDD)

```
Backend
1.  Write failing tests: CmsLayoutService, CmsWidgetService, CmsStyleService
2.  Add migration: cms_layout, cms_layout_widget, cms_widget, cms_menu_item, cms_style
    + alter cms_page (layout_id, style_id, use_theme_switcher_styles)
3.  Implement _slug.py unique_slug helper
4.  Implement repositories (ICmsLayoutRepository, ICmsWidgetRepository,
    ICmsMenuItemRepository, ICmsStyleRepository, ICmsLayoutWidgetRepository)
5.  Implement CmsStyleService → tests green
6.  Implement CmsWidgetService (html + menu + slideshow) → tests green
7.  Implement CmsLayoutService → tests green
8.  Implement admin API endpoints (layouts, widgets, styles)
9.  Implement public API endpoints (GET layout, GET style CSS)
10. Integration tests pass

fe-admin
11. CmsStyleList + CmsStyleEditor (CSS textarea + live preview)
12. CmsWidgetList + CmsWidgetEditor (html type + TipTap HTML tab)
13. CmsMenuTreeEditor (menu widget editor)
14. CmsWidgetEditor slideshow type
15. CmsLayoutList + CmsLayoutEditor (area builder + widget assignments)
16. CmsPageEditor extensions (layout + style selectors + HTML tab)
17. Import/Export wiring in all list views

fe-user
18. CmsWidgetRenderer + CmsAreaHeader/Footer/Hero/CtaBar
19. CmsAreaSlideshow + CmsMenuWidget
20. CmsAreaTwoColumn + CmsAreaThreeColumn
21. CmsPage.vue layout rendering + style injection
22. E2E: create layout → assign widgets → assign layout to page → view in fe-user
23. E2E: export layout → import on fresh slug → verify rename suffix
```