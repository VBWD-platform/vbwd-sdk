# Report 05 — CMS Admin Polish & i18n

**Status:** Done
**Date completed:** 2026-03-08

## Summary

Bug fixes and polish for the CMS admin plugin: widget content editing (TipTap empty init), i18n registration (raw keys showing), import/export buttons, CSS theme tokens, and full multilingual CMS translations.

---

## Fixes

### 1. Widget/Page Content Always Showing Empty (TipTap)

**Root cause:** Two separate issues:

1. **Initialization from `htmlValue`**: When `modelValue` is an empty TipTap doc but `htmlValue` has HTML content (produced by `populate_cms.py`), the editor initialized from the empty doc. Fixed in `initialContent` logic to prefer `htmlValue` when `modelValue` is empty.

2. **Async data timing** (main fix): `TipTapEditor` is instantiated synchronously during component setup, but parent (`CmsWidgetEditor`, `CmsPageEditor`) fetches data in `onMounted` (async). By the time `form.content_html` is set, TipTap was already created with empty props. Added a `watch(() => props.htmlValue, ...)` that:
   - Keeps `rawHtml` in sync (HTML tab always shows correct content)
   - If editor content is still empty and new htmlValue arrives, calls `editor.commands.setContent(val)` to populate the visual tab

**File:** `vbwd-fe-admin/plugins/cms-admin/src/components/TipTapEditor.vue`

### 2. i18n Raw Keys Showing (e.g. `cms.editPage`, `cms.name`)

**Root cause:** `PlatformSDK` was instantiated without the i18n instance:
```typescript
// Before (broken):
const sdk = new PlatformSDK();

// After (fixed):
const sdk = new PlatformSDK(i18n);
```
Without `i18n`, `addTranslations()` collected translations internally but never called `mergeLocaleMessage()`, so vue-i18n had no CMS keys.

**File:** `vbwd-fe-admin/vue/src/main.ts`

---

## New Features

### 3. Import/Export Buttons on CMS List Views

All three list views (Styles, Widgets, Layouts) now have:
- **Import** button in header → opens JSON file picker → POSTs to backend import endpoint → refreshes list
- **Export selected** button in bulk-bar (visible when rows are checked) → POSTs selected IDs to backend export endpoint → downloads JSON (single) or ZIP (multiple)

Backend endpoints used:
- `POST /api/v1/admin/cms/{styles|widgets|layouts}/export` — body: `{"ids": [...]}`
- `POST /api/v1/admin/cms/{styles|widgets|layouts}/import` — body: raw JSON

Export uses `fetch` directly (with auth token from `useAuthStore`) to handle the binary blob response that the ApiClient can't handle.

**Store actions added to** `useCmsAdminStore.ts`:
- `exportStyles(ids)`, `importStyle(file)`
- `exportWidgets(ids)`, `importWidget(file)`
- `exportLayouts(ids)`, `importLayout(file)`
- `_downloadExport(path, filename, ids)` — shared fetch helper

**Files modified:** `CmsStyleList.vue`, `CmsWidgetList.vue`, `CmsLayoutList.vue`, `useCmsAdminStore.ts`

### 4. CSS Design Tokens + Theme-Switcher Readiness

Added CSS custom properties to `App.vue` global style block covering all admin UI colors:

```css
:root {
  --admin-card-bg, --admin-bg, --admin-heading, --admin-text, --admin-muted,
  --admin-border, --admin-border-light, --admin-th-bg, --admin-row-hover,
  --admin-input-border, --admin-focus, --admin-primary, --admin-success,
  --admin-danger, --admin-bulk-bg, --admin-bulk-accent,
  --admin-badge-ok-bg, --admin-badge-ok, --admin-badge-no-bg, --admin-badge-no
}
```

`@media (prefers-color-scheme: dark)` overrides provided for all tokens (dark mode ready).

CMS list views (Style, Widget, Layout) updated to:
- Use CSS variables with light-mode fallback values
- Match `/admin/plans` visual style: white card container, table header `#f8f9fa`, green create button, blue-accent bulk bar
- `CmsStyleList.vue` received its missing `<style scoped>` block (was completely unstyled)

**Files modified:** `App.vue`, `CmsStyleList.vue`, `CmsWidgetList.vue`, `CmsLayoutList.vue`

### 5. Full CMS i18n for All Languages

Created locale files for all 7 non-English languages supported by the admin app:

| File | Language |
|---|---|
| `locales/ru.json` | Russian |
| `locales/de.json` | German |
| `locales/es.json` | Spanish |
| `locales/fr.json` | French |
| `locales/ja.json` | Japanese |
| `locales/zh.json` | Chinese |
| `locales/th.json` | Thai |

All 59 CMS translation keys covered per language.

Updated `index.ts` to register all 8 locales via `sdk.addTranslations()`.

**Files created:** 7 new JSON locale files
**File modified:** `plugins/cms-admin/index.ts`

---

## Files Changed

| File | Change |
|---|---|
| `vue/src/main.ts` | Pass `i18n` to `PlatformSDK` constructor |
| `vue/src/App.vue` | Add CSS design tokens + dark mode overrides |
| `plugins/cms-admin/src/components/TipTapEditor.vue` | Fix async htmlValue watcher + improved init logic |
| `plugins/cms-admin/src/stores/useCmsAdminStore.ts` | Add export/import actions + `_downloadExport` helper |
| `plugins/cms-admin/src/views/CmsStyleList.vue` | Add missing style block + import/export buttons |
| `plugins/cms-admin/src/views/CmsWidgetList.vue` | Update styles to CSS vars + import/export buttons |
| `plugins/cms-admin/src/views/CmsLayoutList.vue` | Update styles to CSS vars + import/export buttons |
| `plugins/cms-admin/index.ts` | Import + register all 8 language locales |
| `plugins/cms-admin/locales/ru.json` | New — Russian CMS translations |
| `plugins/cms-admin/locales/de.json` | New — German CMS translations |
| `plugins/cms-admin/locales/es.json` | New — Spanish CMS translations |
| `plugins/cms-admin/locales/fr.json` | New — French CMS translations |
| `plugins/cms-admin/locales/ja.json` | New — Japanese CMS translations |
| `plugins/cms-admin/locales/zh.json` | New — Chinese CMS translations |
| `plugins/cms-admin/locales/th.json` | New — Thai CMS translations |
