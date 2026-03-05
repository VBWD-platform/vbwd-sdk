# Sprint 22b: User Plugin Config Parity

## Context

Sprint 18 (2026-02-10) built a complete plugin management system for **admin** plugins:
- Central `plugins.json` registry inside `admin/plugins/`
- Central `config.json` for saved config values
- Per-plugin `config.json` (schema: type, default, description)
- Per-plugin `admin-config.json` (UI form layout: tabs, fields)
- Plugin `index.ts` with `activate()`/`deactivate()` lifecycle hooks

The **user** plugins (`landing1`, `checkout`) were created in Sprint 16 with bare-minimum infrastructure — just `index.ts` + Vue component. They lack every piece of the config system.

### Gap Analysis

| Feature | Admin (`admin/plugins/`) | User (`user/plugins/`) |
|---------|-------------------------|----------------------|
| `plugins.json` location | `admin/plugins/plugins.json` | `user/plugins.json` (wrong — at root, not inside `plugins/`) |
| Central `config.json` | `admin/plugins/config.json` | **MISSING** |
| Per-plugin `config.json` | `analytics-widget/config.json` | **MISSING** for both plugins |
| Per-plugin `admin-config.json` | `analytics-widget/admin-config.json` | **MISSING** for both plugins |
| `activate()` / `deactivate()` | Yes (`analytics-widget`) | **MISSING** — `install()` only |
| Plugin name consistency | `analytics-widget` everywhere | `checkout-public` in code vs `checkout` in `plugins.json` |
| Version in `plugins.json` | `"1.0.0"` | `"0.0.0"` (stale, code says `1.0.0`) |

### Goal

Bring user plugin infrastructure to full parity with admin, so Sprint 23 can build the User Plugins management tab without needing to fix structural gaps at the same time.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Write failing tests (RED) before implementation (GREEN), then refactor. Tests for plugin lifecycle hooks and config loading written before updating plugin code. |
| **DRY** | Follow the exact same file structure and JSON schema conventions established in Sprint 18 for admin plugins. No new patterns — mirror what works. |
| **SOLID — SRP** | Each config file has one purpose: `plugins.json` = registry, `config.json` (central) = saved values, per-plugin `config.json` = schema, per-plugin `admin-config.json` = UI layout. |
| **SOLID — OCP** | Plugin config system is open for extension — adding a new user plugin = adding files to `user/plugins/`, zero code changes elsewhere. |
| **SOLID — LSP** | All user plugins implement the same `IPlugin` interface with full lifecycle: `install()`, `activate()`, `deactivate()`. Any plugin is substitutable. |
| **SOLID — ISP** | Config schema is separate from UI layout. A plugin with zero config still works (empty tabs array in `admin-config.json`). Plugins only define what they need. |
| **SOLID — DIP** | Plugin config files are data contracts. The management UI (Sprint 23) depends on these JSON interfaces, not on plugin source code. |
| **Clean Code** | Consistent naming: plugin name in `index.ts` must match directory name and `plugins.json` key. No magic strings — config keys are self-documenting. |
| **Type Safety** | Strict TypeScript — plugin `index.ts` exports must satisfy `IPlugin` interface including `activate()` and `deactivate()`. Config schema types: `string`, `number`, `boolean`, `select`. |
| **Coverage** | Existing 115 user tests must not regress. New tests for plugin lifecycle hooks (~6 tests). |

---

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. Quick local validation (user unit tests)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression (no admin code changes, but verify)
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Full pre-commit check (admin + user)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit

# 4. Core regression
cd vbwd-frontend/core && npx vitest run
```

**Test categories for this sprint:**

| Category | Command | What it covers |
|----------|---------|----------------|
| User unit | `--user --unit` | Plugin lifecycle hooks, config file loading, regression |
| Admin unit | `--admin --unit` | Regression check — admin plugins must not break |
| Core unit | `cd core && npx vitest run` | Regression check |

**Existing test counts (must not regress):**
- Admin: 305 tests
- User: 115 tests
- Core: 289 tests
- Backend: 626 tests

---

## Task 1: Move `plugins.json` into `user/plugins/`

Move `user/plugins.json` → `user/plugins/plugins.json` to match admin convention.

Fix stale data:
- `landing1` version: `"0.0.0"` → `"1.0.0"` (matches `index.ts`)
- `checkout` key: keep as `checkout` (will fix name mismatch in Task 3)

**`user/plugins/plugins.json`:**
```json
{
  "plugins": {
    "landing1": {
      "enabled": true,
      "version": "1.0.0",
      "installedAt": "2026-02-09T09:27:36.268Z",
      "source": "local"
    },
    "checkout": {
      "enabled": true,
      "version": "1.0.0",
      "installedAt": "2026-02-09T09:28:16.651Z",
      "source": "local"
    }
  }
}
```

Update all references to old path:
- `user/vue/src/main.ts` (if it reads `plugins.json`)
- `user/bin/plugin-manager.ts` (CLI tool)

### Files:
- MOVE: `user/plugins.json` → `user/plugins/plugins.json` (update content)
- EDIT: `user/bin/plugin-manager.ts` (update path)
- EDIT: any other imports referencing old `plugins.json` location

---

## Task 2: Create central `user/plugins/config.json`

Central saved config values for all user plugins (same pattern as `admin/plugins/config.json`).

**`user/plugins/config.json`:**
```json
{
  "landing1": {},
  "checkout": {}
}
```

### Files:
- NEW: `user/plugins/config.json`

---

## Task 3: Fix checkout plugin name mismatch

The checkout plugin `index.ts` exports `name: 'checkout-public'` but `plugins.json` registers it as `checkout`. Align to `checkout` (matches directory name).

**`user/plugins/checkout/index.ts`:**
```typescript
export const checkoutPlugin: IPlugin = {
  name: 'checkout',  // was 'checkout-public'
  ...
};
```

Update the route name as well to avoid confusion — keep the route `name: 'checkout-public'` for the Vue route (distinct from the plugin name), but plugin metadata name should match directory.

### Files:
- EDIT: `user/plugins/checkout/index.ts` (name: `'checkout'`)

---

## Task 4: Add `activate()` / `deactivate()` to user plugins

Both user plugins currently only have `install()`. Add lifecycle hooks to match the `IPlugin` contract (same pattern as `analytics-widget`).

**`user/plugins/landing1/index.ts`:**
```typescript
export const landing1Plugin: IPlugin = {
  name: 'landing1',
  version: '1.0.0',
  description: 'Public landing page with tariff plan selection',
  _active: false,

  install(sdk: IPlatformSDK) {
    sdk.addRoute({ ... });
  },

  activate(): void {
    (this as IPlugin & { _active: boolean })._active = true;
  },

  deactivate(): void {
    (this as IPlugin & { _active: boolean })._active = false;
  }
};
```

Same for `checkout/index.ts`.

### Files:
- EDIT: `user/plugins/landing1/index.ts`
- EDIT: `user/plugins/checkout/index.ts`

---

## Task 5: Create per-plugin `config.json` (config schema)

**`user/plugins/landing1/config.json`:**
```json
{
  "heroTitle": {
    "type": "string",
    "default": "Choose Your Plan",
    "description": "Main heading on the landing page"
  },
  "showPrices": {
    "type": "boolean",
    "default": true,
    "description": "Display prices on plan cards"
  },
  "columnsPerRow": {
    "type": "number",
    "default": 3,
    "description": "Number of plan cards per row"
  }
}
```

**`user/plugins/checkout/config.json`:**
```json
{
  "requireTerms": {
    "type": "boolean",
    "default": true,
    "description": "Require terms acceptance before checkout"
  },
  "allowGuestCheckout": {
    "type": "boolean",
    "default": true,
    "description": "Allow checkout without login"
  }
}
```

### Files:
- NEW: `user/plugins/landing1/config.json`
- NEW: `user/plugins/checkout/config.json`

---

## Task 6: Create per-plugin `admin-config.json` (UI form layout)

**`user/plugins/landing1/admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "heroTitle",
          "label": "Hero Title",
          "component": "input",
          "inputType": "text"
        },
        {
          "key": "showPrices",
          "label": "Show Prices",
          "component": "checkbox"
        },
        {
          "key": "columnsPerRow",
          "label": "Columns Per Row",
          "component": "input",
          "inputType": "number",
          "min": 1,
          "max": 4
        }
      ]
    }
  ]
}
```

**`user/plugins/checkout/admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "requireTerms",
          "label": "Require Terms Acceptance",
          "component": "checkbox"
        },
        {
          "key": "allowGuestCheckout",
          "label": "Allow Guest Checkout",
          "component": "checkbox"
        }
      ]
    }
  ]
}
```

### Files:
- NEW: `user/plugins/landing1/admin-config.json`
- NEW: `user/plugins/checkout/admin-config.json`

---

## Task 7: Update `main.ts` — conditional activation from `plugins.json`

Currently user `main.ts` activates ALL plugins unconditionally:

```typescript
// CURRENT (user/vue/src/main.ts) — BAD: ignores enabled flag
for (const plugin of registry.getAll()) {
  await registry.activate(plugin.name);
}
```

Admin `main.ts` reads `plugins.json` and only activates enabled plugins:

```typescript
// ADMIN (admin/vue/src/main.ts) — GOOD: respects enabled flag
const enabledPlugins = pluginsRegistry.plugins as Record<string, { enabled: boolean }>;
for (const [name, entry] of Object.entries(enabledPlugins)) {
  if (entry.enabled) {
    await registry.activate(name);
  }
}
```

Update user `main.ts` to match admin pattern:

1. Import `plugins.json` from new location (`../../plugins/plugins.json`)
2. Read `enabled` flag per plugin
3. Only activate plugins where `enabled === true`
4. Provide `pluginRegistry` and `platformSDK` via `app.provide()` (admin does this, user doesn't)

**Target `user/vue/src/main.ts` bootstrap block:**
```typescript
import pluginsRegistry from '../../plugins/plugins.json';

// ...

const registry = new PluginRegistry();
const sdk = new PlatformSDK();

registry.register(landing1Plugin);
registry.register(checkoutPlugin);

await registry.installAll(sdk);

// Inject plugin routes into the router
for (const route of sdk.getRoutes()) {
  router.addRoute(route as Parameters<typeof router.addRoute>[0]);
}

// Only activate plugins that are enabled in plugins.json
const enabledPlugins = pluginsRegistry.plugins as Record<string, { enabled: boolean }>;
for (const [name, entry] of Object.entries(enabledPlugins)) {
  if (entry.enabled) {
    await registry.activate(name);
  }
}

// Make available via provide/inject
app.provide('pluginRegistry', registry);
app.provide('platformSDK', sdk);

await router.replace(location.pathname + location.search + location.hash);
```

### Files:
- EDIT: `user/vue/src/main.ts`

---

## Task 8: Update `plugin-manager.ts` CLI paths

User CLI currently points to `./plugins.json` (root level). Update to match new location.

**Before:**
```typescript
const cli = new PluginManagerCLI(registry, {
  pluginsDir: './plugins',
  configFile: './plugins.json'      // old path
});
```

**After:**
```typescript
const cli = new PluginManagerCLI(registry, {
  pluginsDir: './plugins',
  configFile: './plugins/plugins.json'  // new path inside plugins/
});
```

### Files:
- EDIT: `user/bin/plugin-manager.ts`

---

## Task 9: Update tests

Update existing plugin tests to verify lifecycle hooks. Add tests for config file presence.

**EDIT: `user/vue/tests/unit/plugins/landing1.spec.ts`:**
- Add test: `landing1Plugin` has `activate()` method
- Add test: `landing1Plugin` has `deactivate()` method
- Add test: calling `activate()` sets `_active` to true
- Add test: calling `deactivate()` sets `_active` to false

**EDIT: `user/vue/tests/unit/plugins/checkout-public.spec.ts`:**
- Same lifecycle tests for `checkoutPlugin`
- Update assertions: plugin name changed from `checkout-public` to `checkout`

**EDIT: `user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts`:**
- Update for conditional activation from `plugins.json`
- Update any references to old `plugins.json` location
- Add test: disabled plugin is NOT activated
- Add test: enabled plugin IS activated

### Files:
- EDIT: `user/vue/tests/unit/plugins/landing1.spec.ts`
- EDIT: `user/vue/tests/unit/plugins/checkout-public.spec.ts`
- EDIT: `user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts`

---

## Implementation Order

1. Task 1 — Move `plugins.json` into `plugins/` (filesystem)
2. Task 2 — Create central `config.json` (filesystem)
3. Task 3 — Fix checkout name mismatch (code)
4. Task 4 — Add activate/deactivate hooks (code)
5. Task 5 — Create per-plugin `config.json` (filesystem)
6. Task 6 — Create per-plugin `admin-config.json` (filesystem)
7. Task 7 — Update `main.ts` conditional activation (code)
8. Task 8 — Update `plugin-manager.ts` CLI paths (code)
9. Task 9 — Update tests

---

## File Summary

| Action | File |
|--------|------|
| MOVE | `user/plugins.json` → `user/plugins/plugins.json` |
| NEW | `user/plugins/config.json` |
| EDIT | `user/plugins/checkout/index.ts` (name fix + lifecycle hooks) |
| EDIT | `user/plugins/landing1/index.ts` (lifecycle hooks) |
| NEW | `user/plugins/landing1/config.json` |
| NEW | `user/plugins/landing1/admin-config.json` |
| NEW | `user/plugins/checkout/config.json` |
| NEW | `user/plugins/checkout/admin-config.json` |
| EDIT | `user/vue/src/main.ts` (conditional activation + provide/inject) |
| EDIT | `user/bin/plugin-manager.ts` (path update) |
| EDIT | `user/vue/tests/unit/plugins/landing1.spec.ts` |
| EDIT | `user/vue/tests/unit/plugins/checkout-public.spec.ts` |
| EDIT | `user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts` |

---

## Post-Sprint File Structure (Target)

```
user/
  plugins/
    plugins.json              ← central registry (moved from user/plugins.json)
    config.json               ← central saved config values (NEW)
    landing1/
      index.ts                ← IPlugin with install + activate + deactivate
      Landing1View.vue
      config.json             ← config schema (NEW)
      admin-config.json       ← UI form layout (NEW)
    checkout/
      index.ts                ← IPlugin with install + activate + deactivate, name='checkout'
      PublicCheckoutView.vue
      config.json             ← config schema (NEW)
      admin-config.json       ← UI form layout (NEW)
```

This mirrors admin's structure exactly:

```
admin/
  plugins/
    plugins.json
    config.json
    analytics-widget/
      index.ts
      AnalyticsWidget.vue
      config.json
      admin-config.json
```

---

## Verification

### Automated tests (must all pass)

```bash
# 1. User unit tests (includes plugin lifecycle tests)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Full pre-commit
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit

# 4. Core regression
cd vbwd-frontend/core && npx vitest run
```

### Manual verification

```bash
# Verify file structure matches target
find user/plugins -type f | sort

# Verify plugins.json is valid JSON with correct data
cat user/plugins/plugins.json | python3 -m json.tool

# Verify all config files are valid JSON
for f in user/plugins/*/config.json user/plugins/*/admin-config.json user/plugins/config.json; do
  echo "Checking $f..." && cat "$f" | python3 -m json.tool > /dev/null && echo "OK"
done

# Rebuild user container and verify app still works
cd vbwd-frontend && docker compose up -d --build user-app
curl -s http://localhost:8080/ | grep -q '<div id="app">' && echo "User app OK"
```
