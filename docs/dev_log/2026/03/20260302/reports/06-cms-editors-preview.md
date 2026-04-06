# CMS Editors: Preview Tabs, Page CSS, and Data Upsert

**Date:** 2026-03-08
**Session:** 06

---

## Overview

This session extended the CMS admin plugin with preview capabilities across all three editor views (widget, layout, page), added page-level CSS editing, and made the populate script idempotent via upserts.

---

## Backend Changes

### 1. `source_css` on `cms_page`

**Model** — `plugins/cms/src/models/cms_page.py`
- Added `source_css = db.Column(db.Text, nullable=True)` after `content_html`
- Added `"source_css": self.source_css` to `to_dict()`

**Service** — `plugins/cms/src/services/cms_page_service.py`
- Added `"source_css"` to the `_apply_data` field list so it is persisted on create and update

**Migration** — `alembic/versions/20260308_cms_page_source_css.py`
- Revision ID: `20260308_cms_page_source_css`
- Revises: `20260308_cms_widget_refactor`
- Adds `source_css TEXT NULL` to `cms_page`

### 2. populate_cms.py — Upsert (idempotent re-runs)

All `_get_or_create_*` helpers were changed from **skip-if-exists** to **upsert**. This is essential because the previous Alembic migration base64-encoded the full HTML (including embedded `<style>` blocks) into `content_json.content`, while the correct format has CSS extracted into `source_css`. Re-running populate now corrects any such rows.

| Helper | Fields updated on existing record |
|---|---|
| `_get_or_create_style` | `name`, `source_css`, `sort_order` |
| `_get_or_create_widget` | `name`; for `html` type: `content_json`, `source_css` |
| `_get_or_create_layout` | `name`, `description`, `areas`, `sort_order` |
| `_get_or_create_page` | `name`, `layout_id`, `style_id`, `content_json`, `content_html`, `meta_description`, `sort_order` |

---

## Frontend Changes (`plugins/cms-admin/src/`)

### 3. TipTapEditor.vue — `hideTabBar` prop + `setFromHtml` method

- **`hideTabBar?: boolean`** prop: when true, the internal Visual/HTML tab switcher is hidden. Used by `CmsPageEditor` which now manages its own tab system.
- **`setFromHtml(html: string)`** exposed method: sets TipTap content from raw HTML and emits both `update:modelValue` and `update:htmlValue`. Called when the user switches from the HTML tab back to WYSIWYG in the page editor.

### 4. CmsWidgetEditor.vue — Preview tab

Added a third **"Preview"** tab for `html`-type widgets.

- Tab switcher now iterates `['HTML', 'CSS', 'Preview']`
- Tab changes go through `onWidgetTabChange()` instead of a direct `v-model`
- On switch to Preview: `updateWidgetPreview()` writes the decoded HTML and CSS into a sandboxed `<iframe>`
- Preview iframe: `sandbox="allow-same-origin"`, 420px height, no border
- `widgetPreviewFrame` ref wires the iframe for programmatic `doc.write()`

```
HTML tab → CodeMirrorEditor (htmlContent)
CSS tab  → CodeMirrorEditor (cssContent) + hint text
Preview  → <iframe sandbox> with <style>css</style><body>html</body>
```

### 5. CmsLayoutEditor.vue — Preview tab

Added a **Builder / Preview** top-level tab switcher above the editor body.

- **Builder tab**: existing meta fields, areas builder, and widget assignments (unchanged)
- **Preview tab**: visual area schematic rendered with CSS classes
  - Each area shown as a labeled card styled by area type (`header`/`footer` = blue, `hero` = green, `content` = yellow, others = grey dashed)
  - Shows area label, type, and assigned widget name (resolved from `store.widgets`)
  - Content-type areas display `[ page content ]` marker instead of a widget assignment
  - `store.fetchWidgets({ per_page: 200 })` is called on mount to populate widget name resolution via `widgetNameFor(id)`

### 6. CmsPageEditor.vue — 5-tab system + CSS tab

Replaced the previous 2-tab (Content / SEO) layout with a **5-tab system**:

| Tab | Content |
|---|---|
| WYSIWYG | `TipTapEditor` with `hide-tab-bar` |
| HTML | `CodeMirrorEditor` bound to `form.content_html` |
| CSS | `CodeMirrorEditor` bound to `form.source_css` |
| SEO | All existing SEO meta fields (unchanged) |
| Preview | Sandboxed `<iframe>` with CSS + HTML |

Tab changes are handled by `onPageTabChange(tab)`:
- `HTML → WYSIWYG`: calls `editorRef.setFromHtml(form.content_html)` to sync TipTap
- `* → Preview`: calls `updatePagePreview()` after `nextTick()` to write iframe content

**`PageForm` interface and initial state** updated to include `source_css: string`.
**Page load** (`onMounted`) maps `(p as any).source_css ?? ''` into the form.

---

## File Index

| File | Change |
|---|---|
| `vbwd-backend/plugins/cms/src/models/cms_page.py` | + `source_css` column + `to_dict` |
| `vbwd-backend/plugins/cms/src/services/cms_page_service.py` | + `source_css` in `_apply_data` |
| `vbwd-backend/alembic/versions/20260308_cms_page_source_css.py` | New migration |
| `vbwd-backend/plugins/cms/src/bin/populate_cms.py` | All helpers → upsert |
| `vbwd-fe-admin/plugins/cms-admin/src/components/TipTapEditor.vue` | `hideTabBar` prop + `setFromHtml` |
| `vbwd-fe-admin/plugins/cms-admin/src/views/CmsWidgetEditor.vue` | Preview tab |
| `vbwd-fe-admin/plugins/cms-admin/src/views/CmsLayoutEditor.vue` | Preview tab (area schematic) |
| `vbwd-fe-admin/plugins/cms-admin/src/views/CmsPageEditor.vue` | 5-tab system + CSS tab |

---

## Architectural Notes

- **Plugin agnosticism maintained**: all changes live inside `plugins/cms/` (backend) and `plugins/cms-admin/` (frontend). Core files untouched.
- **Preview uses `sandbox="allow-same-origin"`**: scripts are disabled in previews, preventing XSS from user-authored HTML while still allowing CSS rendering.
- **TipTap and CodeMirror coexist** in the page editor: WYSIWYG tab is TipTap, HTML/CSS tabs are CodeMirror. Switching WYSIWYG→HTML captures current TipTap HTML; switching back calls `setFromHtml` to re-parse.
- **`source_css` separation** follows the same principle as widgets: structural/layout CSS is kept separate from content HTML, enabling independent editing and clean injection at render time.
