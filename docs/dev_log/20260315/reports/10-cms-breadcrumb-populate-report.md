# Sprint 10 — CMS Breadcrumb & Populate-DB Update — Completion Report
**Date:** 2026-03-15

---

## Summary

Two parallel workstreams completed:

1. **CmsBreadcrumb vue-component** — generic, CMS-store-aware breadcrumb widget usable on any layout. Replaces the former GHRM-specific breadcrumb. Supports URL-hierarchy mode (multi-segment paths) and CMS-metadata mode (flat content pages with category lookup from store).

2. **Populate-DB scripts refresh** — both `populate_cms.py` and `populate_ghrm.py` updated to reflect the current production database state: categories, routing rules, breadcrumbs widget, content-page layout with breadcrumbs area, software package icons, `/software` page, and `we-are-launching-soon` page.

---

## Changes Delivered

### CmsBreadcrumb Component — `vbwd-fe-user/plugins/cms/src/components/CmsBreadcrumb.vue`

**Two rendering modes** based on URL structure:

| URL type | Mode | Source of data |
|---|---|---|
| Single segment (`/about`, `/we-are-launching-soon`) | CMS-metadata | `useCmsStore().currentPage` + `categories` |
| Multi-segment (`/category/fe-admin/pkg`) | URL-based | Route path parts |

**Config props** (all optional, passed via `widget.config`):

| Field | Type | Default | Description |
|---|---|---|---|
| `separator` | string | `/` | Crumb separator character |
| `root_name` | string | `Home` | Label for the root link |
| `root_slug` | string | `/` | URL for the root link |
| `show_category` | bool | `true` | Show first URL segment in multi-segment mode |
| `category_label` | string | auto from slug | Override label for first segment |
| `category_slug` | string | actual path segment | Override URL for first segment link |
| `max_label_length` | number | `60` | Truncate long labels with `…` |
| `css` | string | — | Scoped CSS injected via `<style>` tag |

**Race condition fix** in `useCmsStore.fetchPage()` (`vbwd-fe-user/plugins/cms/src/stores/useCmsStore.ts`):

Categories and page are now fetched in parallel _before_ the layout is loaded, guaranteeing categories are available when the breadcrumb first renders:

```typescript
const [res] = await Promise.all([
  api.get<any>(`/cms/pages/${slug}`),
  this.categories.length ? Promise.resolve() : this.fetchCategories(),
]);
this.currentPage = res;
// layout fetched only after both resolve ↓
await Promise.all([fetchLayout, fetchStyle]);
```

Previously `fetchCategories` was called separately in `CmsPage.vue` `onMounted`, creating a race where the breadcrumb rendered before categories arrived.

**Registration** (`vbwd-fe-user/plugins/cms/index.ts`):
```typescript
import('./src/components/CmsBreadcrumb.vue').then((m) => {
  registerCmsVueComponent('CmsBreadcrumb', m.default);
});
```

---

### Widget Editor — `vbwd-fe-admin/plugins/cms-admin/src/views/CmsWidgetEditor.vue`

New fields in the Breadcrumbs config section (General tab):

| Field | UI | Notes |
|---|---|---|
| `show_category` | Checkbox | Toggle first segment in multi-segment mode |
| `category_label` | Text input | Display name override for first segment |
| `category_slug` | Text input | URL override for first segment link (e.g. `/software`) |

The `category_slug` field solves the case where the public catalog root URL is `/software` but the actual route path is `/category` — the crumb link can be pointed at the correct slug without changing routes.

**CodeMirror overflow fix** — `.editor-pane` flex child required `min-width: 0; overflow: hidden` to prevent the editor from expanding the container when content is wide.

---

### populate_cms.py — `vbwd-backend/plugins/cms/src/bin/populate_cms.py`

| Addition | Detail |
|---|---|
| Imports | `CmsCategory`, `CmsRoutingRule` |
| `_get_or_create_category()` helper | Idempotent category upsert |
| Categories created | `about`, `blog`, `static-pages` |
| `breadcrumbs` widget | `vue-component`, `content_json: {component: CmsBreadcrumb}`, full config + CSS |
| `content-page` layout | Added `breadcrumbs` area + widget assignment |
| Page category assignments | `about/privacy/terms/contact/features` → `about`; `pricing-embedded` → `blog` |
| New page | `we-are-launching-soon` (content-page layout, light-clean, static-pages category) |
| Routing rule | `default` → `home1` (middleware layer) |
| `_get_or_create_page()` | Added `category_id` and `robots` params; updates both on existing rows |

---

### populate_ghrm.py — `vbwd-backend/plugins/ghrm/src/bin/populate_ghrm.py`

**Software package icons** — `icon_url` added to all 18 packages:

| Package | Icon source |
|---|---|
| Stripe | Official (clipartcraft) |
| PayPal | Official (`paypalobjects.com`) |
| Theme-Switcher | Flaticon 4489592 (dark-mode toggle) |
| LLM Chat | Flaticon 4712104 (AI chat) |
| AI Tarot | Flaticon 1913744 (mystical stars) |
| Import-Export | Flaticon 8227945 (existing) |
| Analytics | Flaticon 1546912 (chart) |
| GHRM | GitHub official mark |
| LensForge | Flaticon 685655 (lens/camera) |
| LoopAI Core | Flaticon 4481503 (AI robot) |
| LoopAI View | Flaticon 1087815 (dashboard) |
| Agent Post | Flaticon 1384060 (social/post) |
| OXID Shop Watch | Flaticon 2037082 (e-commerce monitor) |
| ECWatch Core | Flaticon 3281289 (monitoring) |
| ECWatch Web | Flaticon 1828765 (web dashboard) |
| OXID DevChat | Flaticon 4944377 (dev chat) |
| WP Post2MD | WordPress official mark |
| Quantum LLM | Flaticon 1976916 (atom) |

Existing packages: `icon_url` is updated on re-run if the DB value differs from the script.

**Layout updates** — both `ghrm-software-catalogue` and `ghrm-software-detail` layouts updated:
- Added `breadcrumbs` area (type `vue`) between header and content
- Added `breadcrumbs` widget assignment (sort_order 3)
- Existing layouts get `areas` array updated on re-run (not just on creation)

**New `/software` page** — alternate root entry point for the catalogue with `dark-midnight` style. Mirrors `/category` but uses the dark theme as set in production.

**Category sub-pages** — `style_id = light-clean` added to `/category` and all `/category/<slug>` pages.

---

## Files Changed

| File | Change |
|---|---|
| `vbwd-fe-user/plugins/cms/src/components/CmsBreadcrumb.vue` | Rewritten — dual mode, CMS store integration, `category_slug` support |
| `vbwd-fe-user/plugins/cms/src/stores/useCmsStore.ts` | `fetchPage` fetches categories in parallel before layout |
| `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` | Removed redundant `fetchCategories` call |
| `vbwd-fe-user/plugins/cms/index.ts` | Registers `CmsBreadcrumb` on install |
| `vbwd-fe-admin/plugins/cms-admin/src/views/CmsWidgetEditor.vue` | Added `category_label`, `category_slug` fields; CodeMirror overflow fix |
| `vbwd-backend/plugins/cms/src/bin/populate_cms.py` | Categories, breadcrumbs widget, routing rule, `we-are-launching-soon`, category assignments |
| `vbwd-backend/plugins/ghrm/src/bin/populate_ghrm.py` | Icons for all 18 packages, breadcrumbs in layouts, `/software` page |

---

## Behaviour Notes

- **`/about`** → breadcrumb reads `currentPage.category_id`, finds category `About`, shows `Home / About / About Us`
- **`/we-are-launching-soon`** → `Home / Static Pages / We are launching soon!`
- **`/category/fe-admin`** → URL-based: `Home / Software / Fe Admin` (using `category_label` config)
- **`/software`** → single segment, category = `Software Catalogue`, shows `Home / Software Catalogue / Software`
- **Home link** in breadcrumb goes to `root_slug` config value (`/home1` by default). If `/` redirects to `/dashboard`, set `root_slug` to the actual CMS homepage slug.
