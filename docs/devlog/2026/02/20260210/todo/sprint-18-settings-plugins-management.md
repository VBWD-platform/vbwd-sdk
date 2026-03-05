# Sprint 18: Settings / Plugins Management

## Context

The admin panel needs a central place to manage frontend plugins. Currently:
- Plugins are registered via hardcoded imports in `main.ts`
- `plugins.json` lives at `admin/vue/plugins.json` (empty `{}`) and `user/plugins.json` (has landing1, checkout)
- Admin has one plugin (`analytics-widget`) in `admin/plugins/`; user has two (`landing1`, `checkout`) in `user/plugins/`
- Plugins have no config files (`config.json` / `admin-config.json`) yet
- No admin UI exists to view, configure, activate/deactivate, or uninstall plugins

This sprint introduces:
1. A **Plugins tab** under Settings (`/admin/settings` tab "Plugins")
2. A **Plugin Details page** (`/admin/settings/plugins/:pluginName`) with config tabs
3. A **plugin config system** based on `config.json` + `admin-config.json` per plugin
4. A central **`admin/plugins/config.json`** storing saved config values for all plugins
5. Move `plugins.json` from `admin/vue/plugins.json` to `admin/plugins/plugins.json`

### Plugin Discovery

A plugin folder under `admin/plugins/<name>/` is considered valid and appears in the plugins list if it contains at minimum:
- `index.ts` (plugin entry point with IPlugin export)
- `config.json` (default configuration schema)
- `admin-config.json` (admin form layout definition)

### Current Plugin Locations & Files

```
admin/
  vue/
    plugins.json          # MOVE to admin/plugins/plugins.json
  plugins/
    .gitkeep
    analytics-widget/
      index.ts            # IPlugin export
      AnalyticsWidget.vue
user/
  plugins.json            # separate, stays as-is
  plugins/
    landing1/
      index.ts
      Landing1View.vue
    checkout/
      index.ts
      PublicCheckoutView.vue
```

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Write failing tests (RED) before implementation (GREEN), then refactor. Tests for plugins store, Settings Plugins tab, and PluginDetails page all written before the views. |
| **DRY** | Reuse existing Settings.vue patterns (tab structure, lazy-loading, table styles from tokens tab). Plugin config form renderer is a single reusable mechanism, not per-plugin duplication. |
| **SOLID — SRP** | `plugins.ts` store handles data; `Settings.vue` Plugins tab handles list display; `PluginDetails.vue` handles single plugin config/lifecycle. Each config file has one purpose (schema vs form layout vs saved values). |
| **SOLID — OCP** | PluginDetails config form is open for extension (new field components, new tabs via admin-config.json) without modifying the renderer. Adding a new plugin = adding files to `admin/plugins/`, no code changes to Settings or PluginDetails. |
| **SOLID — LSP** | All plugins implement the same IPlugin interface. Config fields of any type (string, number, boolean, select) render through the same form field mechanism. |
| **SOLID — ISP** | Plugin config schema (`config.json`) is separate from admin form layout (`admin-config.json`). Plugins only define what they need — a plugin with zero config still works (empty tabs array). |
| **SOLID — DIP** | Store depends on API abstraction (same `api` client), not concrete HTTP. Views depend on store interface, not JSON file locations. Frontend-only approach is swappable for backend integration. |
| **Clean Code** | Self-documenting component names, consistent `data-testid` attributes, no magic strings (all labels from i18n). Plugin discovery logic is explicit and documented. |
| **Type Safety** | Strict TypeScript — explicit interfaces for PluginEntry, PluginConfigField, AdminConfigTab, PluginDetail. No `any` types. Props and store state fully typed. |
| **Coverage** | 90%+ for plugin store (fetch, save, activate, deactivate). 80%+ for PluginDetails (render tabs, form fields, save, lifecycle actions). Settings tab assertion for new tab. |

---

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# Quick local validation (unit + integration for admin)
cd vbwd-frontend/admin/vue && npx vitest run

# Full pre-commit check (style + unit + integration for admin)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --unit --integration

# Full pre-commit check for both admin and user (ensure no regressions)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit --integration
```

**Test categories for this sprint:**

| Category | Command | What it covers |
|----------|---------|----------------|
| Admin unit | `--admin --unit` | Plugin store actions/getters, plugin bootstrap helpers |
| Admin integration | `--admin --integration` | Settings.vue Plugins tab render, PluginDetails page render + interactions |
| User unit | `--user --unit` | Regression check — user plugins must not break |
| Style | `--admin --style` (default) | ESLint + vue-tsc TypeScript check |

**Test files:**
- EDIT: `admin/vue/tests/integration/Settings.spec.ts` — add `tab-plugins` assertion
- NEW: `admin/vue/tests/unit/stores/plugins.spec.ts` — store CRUD, config merging (defaults + saved)
- NEW: `admin/vue/tests/integration/PluginDetails.spec.ts` — render, tabs, form fields, save, lifecycle

**Existing test counts (must not regress):**
- Admin: 270 tests
- User: 115 tests
- Core: 289 tests
- Backend: 594 tests

---

## Task 1: Move `plugins.json` and Create Plugin Config Files

### 1a. Move `plugins.json`

Move `admin/vue/plugins.json` to `admin/plugins/plugins.json`. This file tracks installed plugin metadata (enabled, version, installedAt, source).

Update all references:
- `admin/vue/bin/plugin-manager.ts` (CLI tool that reads/writes plugins.json)
- `admin/vue/tsconfig.json` / `vite.config.ts` if `plugins.json` path is referenced
- Any imports that resolve `plugins.json`

New location: `admin/plugins/plugins.json`
```json
{
  "plugins": {
    "analytics-widget": {
      "enabled": true,
      "version": "1.0.0",
      "installedAt": "2026-02-10T00:00:00.000Z",
      "source": "local"
    }
  }
}
```

### 1b. Create per-plugin `config.json` (default config schema)

Each plugin MUST have a `config.json` in its root that declares its configurable fields with types, defaults, and descriptions.

**`admin/plugins/analytics-widget/config.json`**:
```json
{
  "refreshInterval": {
    "type": "number",
    "default": 30,
    "description": "Data refresh interval in seconds"
  },
  "showChart": {
    "type": "boolean",
    "default": true,
    "description": "Show chart visualization"
  },
  "maxDataPoints": {
    "type": "number",
    "default": 50,
    "description": "Maximum data points to display"
  }
}
```

### 1c. Create per-plugin `admin-config.json` (form layout)

Describes how config fields are grouped and displayed on the Plugin Details config page. Plugin developers can organize fields into named tabs.

**`admin/plugins/analytics-widget/admin-config.json`**:
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "refreshInterval",
          "label": "Refresh Interval (seconds)",
          "component": "input",
          "inputType": "number",
          "min": 5,
          "max": 300
        },
        {
          "key": "showChart",
          "label": "Show Chart",
          "component": "checkbox"
        }
      ]
    },
    {
      "id": "display",
      "label": "Display",
      "fields": [
        {
          "key": "maxDataPoints",
          "label": "Max Data Points",
          "component": "input",
          "inputType": "number",
          "min": 10,
          "max": 500
        }
      ]
    }
  ]
}
```

### 1d. Create central `admin/plugins/config.json` (saved values)

Stores the actual saved configuration values for all plugins. Keyed by plugin name. When a plugin has no saved config, its defaults from `config.json` are used.

**`admin/plugins/config.json`**:
```json
{
  "analytics-widget": {}
}
```

When admin saves config on the Plugin Details page, values are written here.

### 1e. Add required files to existing admin plugins

The `analytics-widget` plugin already exists at `admin/plugins/analytics-widget/` but only has `index.ts` and `AnalyticsWidget.vue`. For it to be discoverable by the plugin management UI, it needs the two new config files created in 1b and 1c above.

Every plugin under `admin/plugins/` MUST have these three files to appear in the Settings/Plugins list:
- `index.ts` — already exists
- `config.json` — NEW (default config schema, created in 1b)
- `admin-config.json` — NEW (admin form layout, created in 1c)

If a future plugin is added to `admin/plugins/<name>/` without these files, it is treated as **unverified** and does NOT appear in the plugin list. The discovery utility should log a warning for folders missing required files.

**Checklist for `analytics-widget`:**
- [x] `admin/plugins/analytics-widget/index.ts` (exists)
- [x] `admin/plugins/analytics-widget/AnalyticsWidget.vue` (exists)
- [ ] `admin/plugins/analytics-widget/config.json` (create — Task 1b)
- [ ] `admin/plugins/analytics-widget/admin-config.json` (create — Task 1c)

**Register in `plugins.json`:**
The moved `admin/plugins/plugins.json` must include `analytics-widget` as an installed plugin (see 1a content above). Currently `admin/vue/plugins.json` has `"plugins": {}` — update to register `analytics-widget` with `enabled: true`.

### Files:
- MOVE: `admin/vue/plugins.json` -> `admin/plugins/plugins.json` (update content to register analytics-widget)
- NEW: `admin/plugins/analytics-widget/config.json`
- NEW: `admin/plugins/analytics-widget/admin-config.json`
- NEW: `admin/plugins/config.json`
- EDIT: `admin/vue/bin/plugin-manager.ts` (update path to `../../plugins/plugins.json`)
- EDIT: Any other references to old `plugins.json` location

---

## Task 2: Plugin Store (`admin/vue/src/stores/plugins.ts`)

Create a Pinia store that reads plugin data from the filesystem config files and provides state for the Settings/Plugins tab and Plugin Details page.

### State:
```ts
interface PluginEntry {
  name: string;
  version: string;
  description: string;
  author?: string;
  enabled: boolean;
  installedAt: string;
  source: string;
  status: 'active' | 'inactive' | 'error';
}

interface PluginConfigField {
  type: 'string' | 'number' | 'boolean' | 'select';
  default: unknown;
  description: string;
}

interface AdminConfigField {
  key: string;
  label: string;
  component: 'input' | 'checkbox' | 'select' | 'textarea';
  inputType?: string;
  min?: number;
  max?: number;
  options?: { value: string; label: string }[];
}

interface AdminConfigTab {
  id: string;
  label: string;
  fields: AdminConfigField[];
}

interface PluginDetail {
  name: string;
  version: string;
  description: string;
  author?: string;
  enabled: boolean;
  configSchema: Record<string, PluginConfigField>;
  adminConfig: { tabs: AdminConfigTab[] };
  savedConfig: Record<string, unknown>;
}
```

### Actions:
- `fetchPlugins()` — `GET /admin/plugins` -> list of PluginEntry
- `fetchPluginDetail(name: string)` — `GET /admin/plugins/:name` -> PluginDetail (merges config.json, admin-config.json, saved config)
- `savePluginConfig(name: string, config: Record<string, unknown>)` — `PUT /admin/plugins/:name/config`
- `activatePlugin(name: string)` — `POST /admin/plugins/:name/activate`
- `deactivatePlugin(name: string)` — `POST /admin/plugins/:name/deactivate`
- `uninstallPlugin(name: string)` — `POST /admin/plugins/:name/uninstall` (marks as uninstalled in plugins.json, does NOT delete files)

### Note on Backend:
These API endpoints (`/admin/plugins/*`) may not exist yet on the backend. For this sprint, the store should be structured to call these endpoints. If the backend is not ready, we mock them in tests. The admin frontend will be ready to consume them once the backend implements them.

**Alternative (frontend-only, no backend):** If we want this to work without backend endpoints, the store can read from static JSON imports of the config files. This is acceptable for Sprint 18 — we can add backend integration later.

For Sprint 18, implement the **frontend-only** approach:
- Import `plugins.json`, per-plugin `config.json`, `admin-config.json`, and central `config.json` as static JSON
- Use a discovery utility that scans `admin/plugins/` for valid plugin folders (has index.ts + config.json + admin-config.json)
- Provide the same store interface so backend integration is a drop-in replacement later

### Files:
- NEW: `admin/vue/src/stores/plugins.ts`

---

## Task 3: Plugins Tab in Settings.vue

### Template changes:
Add a 4th tab button "Plugins" after "Countries", with `data-testid="tab-plugins"`.

Add a Plugins tab content section (`v-show="activeTab === 'plugins'"`) with:
- Section description text
- Loading/error states (same pattern as tokens/countries)
- Plugins table with sortable columns:
  - Name (sortable)
  - Version (sortable)
  - Status (sortable) — badge: "Active" (green) / "Inactive" (grey) / "Error" (red)
  - Installed (sortable) — formatted date
  - Actions — "View" link to plugin details
- Quick search input above the table (filters by name/description)
- Click on row name navigates to `/admin/settings/plugins/:pluginName`

### Script changes:
- Update `MainTab` type: `'core' | 'tokens' | 'countries' | 'plugins'`
- Import `usePluginsStore`
- Add plugins state: `pluginsLoading`, `pluginsError`, `pluginsLoaded`, `pluginSearchQuery`, `pluginSortKey`, `pluginSortDir`
- Computed: `filteredPlugins`, `sortedPlugins`
- Watcher: lazy-load plugins when plugins tab selected
- Sort handler: `handlePluginSort(key: string)`

### Style changes:
- Reuse existing table styles from tokens tab (`.bundles-table` pattern)
- Add `.plugin-search` input style

### Files:
- EDIT: `admin/vue/src/views/Settings.vue`

---

## Task 4: Plugin Details Page (`PluginDetails.vue`)

### Route:
`/admin/settings/plugins/:pluginName` — new route in router, nested under admin layout.

### Template:
- Back link to Settings (plugins tab)
- Plugin header: name, version, description, status badge
- Action buttons: Activate / Deactivate, Uninstall (with confirm dialog)
- Tab navigation from `admin-config.json` tabs (at minimum one tab "Config")
- For each tab: render form fields dynamically based on `admin-config.json`:
  - `input` (text/number) -> `<input>` with type
  - `checkbox` -> `<input type="checkbox">`
  - `select` -> `<select>` with options
  - `textarea` -> `<textarea>`
- Each field shows label, current value (from saved config, falling back to default), and description
- Save button per tab (or global save)
- Success/error messages

### Script:
- Route param: `pluginName`
- Fetch plugin detail on mount via store
- Local reactive form state initialized from savedConfig merged with defaults
- Save handler writes to store
- Activate/deactivate/uninstall handlers

### Files:
- NEW: `admin/vue/src/views/PluginDetails.vue`

---

## Task 5: Router Updates

### `admin/vue/src/router/index.ts`
Add route for Plugin Details page, placed after the token-bundle routes:
```ts
{
  path: 'settings/plugins/:pluginName',
  name: 'plugin-details',
  component: () => import('@/views/PluginDetails.vue')
}
```

No route needed for the plugins list — it's a tab inside Settings.

### Files:
- EDIT: `admin/vue/src/router/index.ts`

---

## Task 6: i18n — All Locale Files

Add keys for:
- `settings.tabs.plugins` — "Plugins" tab label
- `plugins.title` — "Installed Plugins"
- `plugins.description` — "Manage installed plugins, view configuration, and control plugin lifecycle."
- `plugins.search` — "Search plugins..."
- `plugins.noPlugins` — "No plugins installed"
- `plugins.columns.name` — "Name"
- `plugins.columns.version` — "Version"
- `plugins.columns.status` — "Status"
- `plugins.columns.installed` — "Installed"
- `plugins.columns.actions` — "Actions"
- `plugins.view` — "View"
- `plugins.active` — "Active"
- `plugins.inactive` — "Inactive"
- `plugins.error` — "Error"
- `plugins.detail.title` — "Plugin Details"
- `plugins.detail.backToPlugins` — "Back to Plugins"
- `plugins.detail.activate` — "Activate"
- `plugins.detail.deactivate` — "Deactivate"
- `plugins.detail.uninstall` — "Uninstall"
- `plugins.detail.confirmDeactivate` — "Are you sure you want to deactivate this plugin?"
- `plugins.detail.confirmUninstall` — "Are you sure you want to uninstall this plugin? The plugin files will remain in the codebase."
- `plugins.detail.configSaved` — "Configuration saved successfully"
- `plugins.detail.saveConfig` — "Save Configuration"
- `plugins.detail.saving` — "Saving..."

### Files:
- EDIT: `admin/vue/src/i18n/locales/en.json`
- EDIT: `admin/vue/src/i18n/locales/de.json`
- EDIT: `admin/vue/src/i18n/locales/fr.json`
- EDIT: `admin/vue/src/i18n/locales/es.json`
- EDIT: `admin/vue/src/i18n/locales/ru.json`
- EDIT: `admin/vue/src/i18n/locales/zh.json`
- EDIT: `admin/vue/src/i18n/locales/ja.json`
- EDIT: `admin/vue/src/i18n/locales/th.json`

---

## Task 7: Tests

### Unit tests:
- `admin/vue/tests/integration/Settings.spec.ts` — add assertion for `tab-plugins` existence
- NEW: `admin/vue/tests/unit/stores/plugins.spec.ts` — store actions, getters
- NEW: `admin/vue/tests/integration/PluginDetails.spec.ts`:
  - renders plugin header (name, version, description)
  - renders config tabs from admin-config.json
  - renders form fields per tab
  - saves config on button click
  - shows activate/deactivate buttons based on status
  - shows uninstall with confirmation

### Files:
- EDIT: `admin/vue/tests/integration/Settings.spec.ts`
- NEW: `admin/vue/tests/unit/stores/plugins.spec.ts`
- NEW: `admin/vue/tests/integration/PluginDetails.spec.ts`

---

## Implementation Order

1. Task 1 — Move plugins.json, create config files (filesystem setup)
2. Task 2 — Plugin store (data layer)
3. Task 6 — i18n keys (needed by UI)
4. Task 3 — Plugins tab in Settings (list view)
5. Task 5 — Router update (details route)
6. Task 4 — PluginDetails page (detail view + config form)
7. Task 7 — Tests

---

## File Summary

| Action | File |
|--------|------|
| MOVE | `admin/vue/plugins.json` -> `admin/plugins/plugins.json` |
| NEW | `admin/plugins/analytics-widget/config.json` |
| NEW | `admin/plugins/analytics-widget/admin-config.json` |
| NEW | `admin/plugins/config.json` |
| EDIT | `admin/vue/bin/plugin-manager.ts` (update plugins.json path) |
| NEW | `admin/vue/src/stores/plugins.ts` |
| EDIT | `admin/vue/src/views/Settings.vue` (add Plugins tab) |
| NEW | `admin/vue/src/views/PluginDetails.vue` |
| EDIT | `admin/vue/src/router/index.ts` (add plugin-details route) |
| EDIT | `admin/vue/src/i18n/locales/*.json` (8 files) |
| EDIT | `admin/vue/tests/integration/Settings.spec.ts` |
| NEW | `admin/vue/tests/unit/stores/plugins.spec.ts` |
| NEW | `admin/vue/tests/integration/PluginDetails.spec.ts` |

---

## Verification

### Automated tests (must all pass)

```bash
# 1. Quick local unit + integration (admin only)
cd vbwd-frontend/admin/vue && npx vitest run

# 2. Full pre-commit check: style + unit + integration (admin + user)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit --integration

# 3. Core lib regression check
cd vbwd-frontend/core && npx vitest run
```

### Manual smoke test

```bash
cd vbwd-frontend && docker compose up -d --build admin-app
```

1. Navigate to `http://localhost:8081/admin/settings`
2. Verify 4 tabs: Core Settings, Token Bundles, Countries, Plugins
3. Click **Plugins** tab
4. Verify `analytics-widget` appears in the table with status "Active", version "1.0.0"
5. Use quick search to filter — type "analytics", verify row stays; type "xyz", verify empty state
6. Click column headers to sort — verify sort toggles asc/desc
7. Click `analytics-widget` name or "View" -> **Plugin Details** page
8. Verify header: name, version, description, status badge
9. Verify Config tabs: "General" and "Display" (from `admin-config.json`)
10. Verify form fields: Refresh Interval (number input), Show Chart (checkbox), Max Data Points (number input)
11. Change a value, click Save, verify success message
12. Click Deactivate, confirm dialog, verify status changes to "Inactive"
13. Click Activate, verify status changes back to "Active"
14. Navigate back to Settings/Plugins tab, verify status column reflects changes
