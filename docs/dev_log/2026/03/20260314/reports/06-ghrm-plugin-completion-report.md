# Report 06 — GHRM Plugin Completion
**Date:** 2026-03-14

---

## Summary

The GHRM (GitHub Repo Manager) plugin is considered feature-complete for v1. This report covers all work done after the initial production fix (Report 05).

---

## 1. Plugin Manager Config Bug (Core Fix)

**File:** `src/plugins/manager.py`

`load_persisted_state()` was reading each plugin's config from `config.json` into `PluginConfigEntry.config` but then only calling `plugin.enable()` — never `plugin.initialize(config)`. The config from `config.json` was silently discarded for all plugins at every startup.

**Fix:** Before `plugin.enable()`, call `plugin.initialize(config.config)` when config is non-empty. This correctly merges `DEFAULT_CONFIG` with the persisted config via each plugin's overridden `initialize()`.

**Impact:** All plugins were affected — they all ran with DEFAULT_CONFIG only. GHRM credentials were never loaded, so `_make_github_client()` always raised `GithubNotConfiguredError`.

---

## 2. `_cfg()` Wrong Import Path

**File:** `plugins/ghrm/src/routes.py`

`_cfg()` was importing `plugin_manager` from `src.plugins.manager` as a module-level name — that name does not exist at module scope. The `PluginManager` instance lives on `current_app.plugin_manager`. The import failed silently, returning `{}`.

**Fix:** Use `getattr(current_app, "plugin_manager", None)`.

Also fixed: `plugin.config` → `plugin._config` (the `BasePlugin` class exposes `_config` directly; there is no `config` property).

---

## 3. Partial Sync — Preview & Field-Level Sync

### Backend — `SoftwarePackageService` (new methods)

| Method | Description |
|--------|-------------|
| `preview_readme(pkg_id)` | Fetch README.md from GitHub without writing to DB |
| `preview_changelog(pkg_id)` | Fetch CHANGELOG.md (returns `None` if absent) |
| `preview_screenshots(pkg_id)` | Fetch screenshot URL list from `docs/screenshots/` |
| `sync_field(pkg_id, field)` | Persist a single field (`readme`\|`changelog`\|`screenshots`) and update `last_synced_at` |

All methods raise `GhrmSyncAuthError` when GitHub App is not configured, `GhrmPackageNotFoundError` when the package is missing.

### Backend — new routes

| Method | Route | Description |
|--------|-------|-------------|
| `GET` | `/api/v1/admin/ghrm/packages/<id>/preview/<field>` | Returns `{"content": "..."}` or `{"urls": [...]}` |
| `POST` | `/api/v1/admin/ghrm/packages/<id>/sync/<field>` | Persists single field, returns `{"ok": true, "sync": {...}}` |

Returns 400 for invalid fields, 404 for unknown package, 503 when GitHub App is not configured.

### Frontend — `GhrmSoftwareTab.vue` (fe-admin)

Three new buttons alongside "Sync Now": **Sync README**, **Sync Changelog**, **Sync Screenshots**.

Each button:
1. Fetches a preview from `GET .../preview/<field>` — shows "Fetching..." while loading
2. Displays an inline preview panel: markdown in `<pre>` for text fields, `<img>` thumbnails for screenshots
3. "Apply" button persists via `POST .../sync/<field>` — shows "Applying..."
4. "Dismiss" button closes the panel without saving

### Tests

- 10 new unit tests (`TestPreviewReadme`, `TestPreviewChangelog`, `TestPreviewScreenshots`, `TestSyncField`)
- 12 new integration tests in `test_ghrm_preview_sync_api.py` (skip gracefully without a running backend)
- All 49 GHRM unit tests pass

---

## 4. Markdown Rendering — Full GFM

**File:** `plugins/ghrm/src/components/GhrmMarkdownRenderer.vue` (fe-user)

Replaced hand-rolled regex parser with `marked` (GFM parser) + `DOMPurify` (XSS sanitization).

**Before:** Fenced code blocks lost their language tag; no table support; broken list grouping; no blockquote; fragile paragraph handling.

**After:**
- Fenced code blocks retain language identifier (`class="language-yaml"` on `<code>`)
- Full GFM: tables, blockquotes, ordered lists, strikethrough, line breaks, horizontal rules
- External links get `target="_blank" rel="noopener noreferrer"` automatically
- All HTML sanitized via DOMPurify
- Proper styling for all elements (tables, blockquotes, images)

---

## 5. Override vs Cached Data Clarification

`get_package()` returns `override_readme or cached_readme`. When `override_readme` was manually set to old placeholder content, it masked the freshly synced `cached_readme`. Cleared `override_readme` for the `loopai-core` package (it was set to a 477-char placeholder from testing).

**Note for future:** The admin UI should expose override fields so admins can clear them when they want GitHub content to take over again.

---

## 6. Install Tab Removed

The **Install** tab was removed from `GhrmPackageDetail.vue` (fe-user). The install flow (deploy token, connect GitHub) is a future feature pending the full subscriber access UX.

---

## Pre-Commit Status

`./bin/pre-commit-check.sh --quick` — **PASS** (1086 unit tests, 5 skipped)

---

## Known Remaining Issue

**Get Package button** — the CTA on the package detail page passes `pkg.id` (GHRM software package UUID) to `/checkout?tarif_plan_id=` instead of `pkg.tariff_plan_id`. Also the checkout shows only the single linked plan, with no context for the user. Tracked in Sprint 06.
