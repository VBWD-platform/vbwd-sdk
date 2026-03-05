# Sprint 19 Report — Backend Demo Plugin & Admin/Backend Plugin Tabs

**Date:** 2026-02-10
**Status:** DONE
**Priority:** HIGH

---

## Summary

Split Settings into two plugin tabs: "Admin Plugins" (local JSON) and "Backend Plugins" (API-based). Created backend demo plugin with route, admin plugins API (list, enable, disable), and dashboard widget visibility filtering by enabled plugins. All plugin blueprints registered at startup with route handlers checking enabled status.

---

## Changes

### Task 1: Backend Demo Plugin
- `plugins/demoplugin/__init__.py` — `DemoPlugin(BasePlugin)` with metadata, blueprint, URL prefix
- `plugins/demoplugin/routes.py` — `GET /api/v1/backend-demo-plugin` returns success if enabled, 404 if disabled
- `plugins/__init__.py` — package init for plugin discovery

### Task 2: Admin Plugins API
- `GET /api/v1/admin/plugins` — lists all backend plugins with name, version, status, dependencies
- `POST /api/v1/admin/plugins/<name>/enable` — enables a plugin
- `POST /api/v1/admin/plugins/<name>/disable` — disables a plugin
- Route: `src/routes/admin/plugins.py`

### Task 3: Settings Backend Plugins Tab
- Settings.vue split into "Admin Plugins" and "Backend Plugins" tabs
- Backend plugins tab fetches from API, shows status badges, enable/disable buttons
- Admin plugins tab uses local JSON (unchanged from Sprint 18)

### Task 4: Blueprint Registration at Startup
- All plugin blueprints registered in `app.py` at startup (Flask can't register after first request)
- Route handlers check `plugin.status != PluginStatus.ENABLED` and return 404 if disabled

### Task 5: Dashboard Widget Visibility
- Dashboard plugin widgets filtered by enabled admin plugins

---

## Files Changed

### New (4):
| File | Purpose |
|------|---------|
| `plugins/demoplugin/__init__.py` | DemoPlugin class definition |
| `plugins/demoplugin/routes.py` | Demo plugin API endpoint |
| `plugins/__init__.py` | Package init for discovery |
| `src/routes/admin/plugins.py` | Admin plugins API routes |

### Modified (4):
| File | Change |
|------|--------|
| `src/app.py` | Plugin discovery, blueprint registration, CLI |
| `src/routes/admin/__init__.py` | Export admin_plugins_bp |
| `admin/vue/src/views/Settings.vue` | Backend Plugins tab |
| `admin/vue/src/views/Dashboard.vue` | Widget visibility filter |

---

## Test Results

```
Admin:   295 tests (29 files) — all passing
Backend: 594 tests — all passing (3 pre-existing mock_payment failures excluded)
```
