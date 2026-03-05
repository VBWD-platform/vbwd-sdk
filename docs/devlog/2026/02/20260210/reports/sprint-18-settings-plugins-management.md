# Sprint 18 Report — Settings / Plugins Management

**Date:** 2026-02-10
**Status:** DONE
**Priority:** HIGH

---

## Summary

Created admin Settings "Plugins" tab for managing frontend plugins, with a plugin detail page, dynamic config form rendering, and a JSON-based plugin configuration system. Moved Countries from a standalone route into a Settings tab. Added i18n keys to all 8 locales. Total: 295 admin tests.

---

## Changes

### Task 1: Plugin Config System
- `admin/plugins/plugins.json` — central plugin registry (name → {enabled, version, installedAt, source})
- `admin/plugins/config.json` — saved config values per plugin
- Per-plugin `config.json` (schema: type, default, description) + `admin-config.json` (UI layout: tabs, fields)
- Pinia store `stores/plugins.ts` — fetchPlugins, fetchPluginDetail, savePluginConfig, togglePlugin

### Task 2: Settings Plugins Tab
- Replaced standalone Countries route with a Settings tab
- Added "Plugins" tab to Settings.vue showing plugin list with name, version, status badge, toggle switch
- Plugin names are router-links to detail pages

### Task 3: Plugin Details Page (`PluginDetails.vue`)
- Route: `/admin/settings/plugins/:pluginName`
- Renders dynamic config form from `adminConfig.tabs[].fields[]`
- Supports input (text/number), checkbox, select, textarea field components
- Config values initialized from savedConfig over schema defaults
- Save config via pluginsStore

### Task 4: i18n
- Added `plugins.*` keys to all 8 locales (en, de, fr, es, ru, zh, ja, th)

---

## Files Changed

### New (4):
| File | Purpose |
|------|---------|
| `admin/vue/src/stores/plugins.ts` | Pinia store for plugin management |
| `admin/vue/src/views/PluginDetails.vue` | Plugin config detail page |
| `admin/plugins/plugins.json` | Frontend plugin registry |
| `admin/plugins/config.json` | Frontend saved config values |

### Modified (10):
| File | Change |
|------|--------|
| `admin/vue/src/views/Settings.vue` | Added Plugins tab, moved Countries to tab |
| `admin/vue/src/router/index.ts` | Added plugin-details route, removed countries route |
| `admin/vue/src/i18n/locales/en.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/de.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/fr.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/es.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/ru.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/zh.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/ja.json` | plugins.* keys |
| `admin/vue/src/i18n/locales/th.json` | plugins.* keys |

---

## Test Results

```
Admin:   295 tests (29 files) — all passing
Backend: 594 tests — all passing
```
