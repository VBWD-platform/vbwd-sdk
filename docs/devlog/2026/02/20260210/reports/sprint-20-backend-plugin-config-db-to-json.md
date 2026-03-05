# Sprint 20 Report — Backend Plugin Config DB→JSON Refactor

**Date:** 2026-02-10
**Status:** DONE
**Priority:** HIGH

---

## Summary

Refactored backend plugin configuration from PostgreSQL persistence to JSON file-based persistence. Created abstract PluginConfigStore interface + DTO, JsonFilePluginConfigStore, PluginConfigSchemaReader, expanded admin API with config detail/save endpoints, created BackendPluginDetails.vue, and added i18n keys. TDD approach throughout.

---

## Changes

### Phase 1: Abstract Interface + DTO
- `PluginConfigEntry` dataclass (plugin_name, status, config)
- `PluginConfigStore` ABC with 6 abstract methods (get_enabled, save, get_by_name, get_all, get_config, save_config)
- 7 unit tests

### Phase 2: DB Repo LSP Compliance
- `PluginConfigRepository` now extends `PluginConfigStore`
- Returns `PluginConfigEntry` DTOs, added `get_config()`/`save_config()` wrappers
- Marked as deprecated in favor of JSON store

### Phase 3: JSON File Config Store
- `JsonFilePluginConfigStore` reads/writes `plugins.json` + `config.json`
- Atomic writes via `tempfile.mkstemp` + `os.replace`
- 16 unit tests

### Phase 4: Config Schema Reader
- `PluginConfigSchemaReader` reads per-plugin `config.json` (schema) + `admin-config.json` (UI layout)
- Scans directories, normalizes plugin names to directory names
- 8 unit tests

### Phase 5: PluginManager Type Hint
- Changed `config_repo` parameter type to `Optional[PluginConfigStore]`

### Phase 6: Wired JSON Store in app.py
- Replaced `PluginConfigRepository(db.session)` with `JsonFilePluginConfigStore`
- Added `PluginConfigSchemaReader`, set `app.config_store` and `app.schema_reader`

### Phase 7: Expanded Admin API
- `GET /admin/plugins/<name>` — returns configSchema, adminConfig, savedConfig
- `PUT /admin/plugins/<name>/config` — saves config values
- `hasConfig` flag on list endpoint
- 5 unit tests

### Phase 8: BackendPluginDetails.vue
- Route: `/admin/settings/backend-plugins/:pluginName`
- Fetches from API, renders config tabs/fields, save/enable/disable
- Same dynamic form pattern as PluginDetails.vue (input, checkbox, select, textarea)
- 10 unit tests

### Phase 9: Router + Settings Links + i18n
- Router: added `backend-plugin-details` route
- Settings: backend plugin names → router-links
- `backendPlugins.detail.*` keys added to all 8 locales

### Phase 10-11: JSON Data Files + DemoPlugin Config
- `plugins/plugins.json` — analytics (enabled), backend-demo-plugin (disabled)
- `plugins/config.json` — saved config values
- `plugins/demoplugin/config.json` — greeting + requireAdmin schema
- `plugins/demoplugin/admin-config.json` — General tab with 2 fields
- DemoPlugin route reads greeting from config_store

---

## Files Changed

### New (12):
| File | Purpose |
|------|---------|
| `src/plugins/config_store.py` | PluginConfigStore ABC + PluginConfigEntry DTO |
| `src/plugins/json_config_store.py` | JSON file-based config store |
| `src/plugins/config_schema.py` | Per-plugin config/admin-config reader |
| `tests/unit/plugins/test_plugin_config_store_interface.py` | 7 tests |
| `tests/unit/plugins/test_json_file_plugin_config_store.py` | 16 tests |
| `tests/unit/plugins/test_plugin_config_schema.py` | 8 tests |
| `tests/unit/routes/test_admin_plugins_routes.py` | 13 tests |
| `admin/vue/src/views/BackendPluginDetails.vue` | Backend plugin config detail page |
| `admin/vue/tests/unit/views/BackendPluginDetails.spec.ts` | 10 tests |
| `plugins/plugins.json` | Plugin registry |
| `plugins/config.json` | Saved config values |
| `plugins/demoplugin/config.json` | Config schema |
| `plugins/demoplugin/admin-config.json` | Admin UI layout |

### Modified (12):
| File | Change |
|------|--------|
| `src/plugins/manager.py` | config_repo type → PluginConfigStore |
| `src/app.py` | JSON store wiring, removed providers discover |
| `src/routes/admin/plugins.py` | Detail + config endpoints, hasConfig flag |
| `src/repositories/plugin_config_repository.py` | Extends PluginConfigStore (LSP) |
| `plugins/demoplugin/routes.py` | Reads config from config_store |
| `admin/vue/src/router/index.ts` | backend-plugin-details route |
| `admin/vue/src/views/Settings.vue` | Backend plugin router-links |
| `admin/vue/src/i18n/locales/en.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/de.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/fr.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/es.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/ru.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/zh.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/ja.json` | backendPlugins.detail keys |
| `admin/vue/src/i18n/locales/th.json` | backendPlugins.detail keys |

---

## Test Results

```
Admin:   305 tests (29 files) — all passing (+10 new)
Backend: 626 tests — all passing (+55 new, 3 pre-existing mock_payment failures excluded)
Total:   931 admin+backend tests
```
