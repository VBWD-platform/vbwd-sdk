# Sprint 21 Report — Plugin Multi-Worker Bugfix

**Date:** 2026-02-10
**Status:** DONE
**Priority:** CRITICAL

---

## Summary

Fixed two critical bugs in the backend plugin system: (1) 400 BAD REQUEST on enable/disable from admin UI caused by strict state machine + Gunicorn multi-worker in-memory state divergence, (2) plugin status not syncing between frontend and backend because admin routes read in-memory state instead of shared JSON config_store. Also fixed analytics plugin discovery (missing `__init__.py`), removed stale `src.plugins.providers` reference, and fixed JSON file permissions.

---

## Bugs Fixed

### Bug 1: 400 BAD REQUEST on Enable/Disable
**Root cause:** Gunicorn runs 4 workers, each with separate in-memory plugin state. `base.py` enforces strict state transitions: `enable()` requires INITIALIZED, `disable()` requires ENABLED. When worker A enables a plugin, workers B-D still have the old state. A subsequent disable request hitting worker B fails because the plugin is INITIALIZED (not ENABLED) in that worker's memory.

**Fix:** Enable/disable routes now write to `config_store` (shared JSON file) **first** as the source of truth, then do best-effort in-memory sync via `_sync_in_memory()` helper that handles all state transitions gracefully.

### Bug 2: Status Not Syncing Between Frontend and Backend
**Root cause:** `list_plugins` and `get_plugin_detail` routes read status from in-memory `plugin.status` instead of the shared JSON `config_store`. Each worker returns its own stale in-memory state.

**Fix:** Added `_get_persisted_status()` helper that reads from `config_store.get_by_name()`. Both list and detail routes now use this for consistent cross-worker status.

### Bug 3: Analytics Plugin Not Discovered
**Root cause:** `plugins/analytics/` had no `__init__.py`. The `discover()` method only finds `BasePlugin` subclasses defined in `__init__.py` (due to `obj.__module__ != full_module` check). The class was in `analytics_plugin.py` which was never scanned.

**Fix:** Moved `AnalyticsPlugin` class into `plugins/analytics/__init__.py`, deleted the duplicate `analytics_plugin.py`.

### Bug 4: Stale `src.plugins.providers` Reference
**Root cause:** `app.py` called `plugin_manager.discover("src.plugins.providers")` but the directory was removed. Logged warning on every worker boot.

**Fix:** Removed the discover call and the stale directory reference from `PluginConfigSchemaReader` init.

### Bug 5: JSON Files Unreadable From Host
**Root cause:** `tempfile.mkstemp` creates files with `0600` permissions. Since Docker runs as root, atomic writes via `os.replace` produced root-owned `0600` files invisible to the host user.

**Fix:** Added `os.chmod(tmp_path, 0o666)` before `os.replace` in both `_write_plugins()` and `_write_config()`.

---

## Changes

### `src/routes/admin/plugins.py` — Config-store-first architecture
- `_get_persisted_status(plugin_name)` — reads status from shared JSON config_store
- `_sync_in_memory(plugin, target_enabled)` — best-effort in-memory state sync
- `list_plugins` / `get_plugin_detail` — use `_get_persisted_status()` instead of `plugin.status`
- `enable_plugin` / `disable_plugin` — write to config_store first, then `_sync_in_memory()`

### `plugins/demoplugin/routes.py` — Config-store check
- Checks `config_store.get_by_name()` for enabled status instead of in-memory `plugin.status`
- Removed unused `PluginStatus` import

### `plugins/analytics/__init__.py` — Plugin discovery fix
- Moved `AnalyticsPlugin` class from `analytics_plugin.py` into `__init__.py`
- Deleted `analytics_plugin.py`

### `src/plugins/json_config_store.py` — File permissions
- Added `os.chmod(tmp_path, 0o666)` in `_write_plugins()` and `_write_config()`

### `src/app.py` — Cleanup
- Removed `plugin_manager.discover("src.plugins.providers")` (directory doesn't exist)
- Removed `src/plugins/providers` from `PluginConfigSchemaReader` search dirs

### `tests/unit/routes/test_admin_plugins_routes.py` — Multi-worker tests
- Added `_make_config_store()` helper for mocking config_store with `PluginConfigEntry`
- Added `TestEnablePlugin` — tests config_store persistence on enable
- Added `TestDisablePlugin` — tests config_store persistence on disable, **including test that disable does NOT 400 from INITIALIZED state** (the multi-worker scenario)
- Updated existing tests to mock `config_store.get_by_name()` for status reads
- 13 total tests (was 5)

---

## Files Changed

### New (0)

### Deleted (1):
| File | Reason |
|------|--------|
| `plugins/analytics/analytics_plugin.py` | Moved into `__init__.py` |

### Modified (6):
| File | Change |
|------|--------|
| `src/routes/admin/plugins.py` | Config-store-first for status reads + writes |
| `plugins/demoplugin/routes.py` | Config-store check instead of in-memory |
| `plugins/analytics/__init__.py` | AnalyticsPlugin class (was missing) |
| `src/plugins/json_config_store.py` | `os.chmod(0o666)` on atomic writes |
| `src/app.py` | Removed stale providers references |
| `tests/unit/routes/test_admin_plugins_routes.py` | Multi-worker tests (+8 tests) |

---

## Test Results

```
Admin:   305 tests (29 files) — all passing
Backend: 626 tests — all passing (3 pre-existing mock_payment failures excluded)
```

---

## Architecture Note

The plugin system now follows a **config-store-first** pattern:
- **Source of truth:** `plugins/plugins.json` (shared JSON file on disk)
- **In-memory state:** Best-effort sync per worker, not authoritative
- **Reads (list/detail):** Always from config_store
- **Writes (enable/disable):** config_store first, then in-memory sync
- This is robust with Gunicorn's multi-worker architecture (4 workers = 4 separate memory spaces)
