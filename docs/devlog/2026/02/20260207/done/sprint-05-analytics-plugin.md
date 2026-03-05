# Sprint 05 — Analytics Plugin (Plugin System Validation)

**Priority:** HIGH
**Goal:** Validate plugin system readiness by creating a minimal analytics plugin for both backend and admin frontend. The plugin adds one dashboard tile showing "Plugin Active Sessions" count.

**Principles:** TDD-first, SOLID, DRY, Liskov Substitution, DI, Clean Code, No Overengineering

---

## Overview

Two plugins:
1. **Backend** `analytics` plugin — provides a new API endpoint `GET /api/v1/plugins/analytics/active-sessions`
2. **Admin** `analytics-widget` plugin — adds a dashboard tile consuming that endpoint

Both plugins must be installable, activatable, and deactivatable via their respective management systems. This sprint proves the plugin pipeline works end-to-end.

---

## Phase 1: Backend Plugin

### 1.1 Unit Tests (RED) — Plugin Structure

**File:** `vbwd-backend/tests/unit/plugins/test_analytics_plugin.py`

```
Tests to write FIRST:

test_analytics_plugin_has_correct_metadata
  - metadata.name == "analytics"
  - metadata.version == "1.0.0"
  - metadata.author == "VBWD Team"
  - metadata.dependencies == []

test_analytics_plugin_extends_base_plugin
  - isinstance(plugin, BasePlugin) == True  # Liskov

test_analytics_plugin_lifecycle
  - initial status == DISCOVERED
  - after initialize() → INITIALIZED
  - after enable() → ENABLED
  - after disable() → DISABLED

test_analytics_plugin_on_enable_registers_handler
  - on_enable() should register event handler or set internal flag

test_analytics_plugin_on_disable_cleans_up
  - on_disable() should deregister handler or clear flag

test_analytics_plugin_get_active_sessions_returns_dict
  - get_active_sessions() returns {"count": int, "source": "plugin"}

test_analytics_plugin_registers_with_manager
  - PluginManager.register_plugin(plugin) succeeds
  - PluginManager.get_plugin("analytics") returns the plugin

test_analytics_plugin_full_lifecycle_via_manager
  - register → initialize → enable → verify enabled → disable → verify disabled
```

### 1.2 Implementation (GREEN)

**File:** `vbwd-backend/src/plugins/providers/analytics_plugin.py`

```python
# Minimal implementation:
class AnalyticsPlugin(BasePlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="analytics",
            version="1.0.0",
            author="VBWD Team",
            description="Dashboard analytics widget — active sessions count",
        )

    def get_active_sessions(self) -> dict:
        """Return active sessions count. Uses injected db session if available."""
        # Query active subscriptions as proxy for "active sessions"
        count = self._config.get("session_count", 0)
        if self._get_count:
            count = self._get_count()
        return {"count": count, "source": "plugin"}
```

Key design decisions:
- **Liskov:** `AnalyticsPlugin` is a proper `BasePlugin` — substitutable anywhere BasePlugin is expected
- **DI:** Count function injected via config or callable, not hardcoded DB access
- **SRP:** Plugin only provides data; route handles HTTP; dashboard handles display
- **No overengineering:** No abstract AnalyticsProviderPlugin base class — one concrete plugin is enough

### 1.3 Integration Test — Plugin API Route

**File:** `vbwd-backend/tests/integration/test_analytics_plugin_route.py`

```
Tests to write FIRST:

test_analytics_endpoint_returns_200_when_plugin_enabled
  - GET /api/v1/plugins/analytics/active-sessions → 200 + {"count": N, "source": "plugin"}

test_analytics_endpoint_returns_404_when_plugin_disabled
  - Disable plugin → GET /api/v1/plugins/analytics/active-sessions → 404

test_analytics_endpoint_requires_admin_auth
  - No token → 401
  - User token → 403
  - Admin token → 200
```

### 1.4 Route Implementation

**File:** `vbwd-backend/src/routes/plugins/analytics.py`

```python
# Minimal route:
@analytics_bp.route("/active-sessions", methods=["GET"])
@require_auth
@require_admin
def get_active_sessions():
    manager = current_app.container.plugin_manager()
    plugin = manager.get_plugin("analytics")
    if not plugin or plugin.status != PluginStatus.ENABLED:
        return jsonify({"error": "Analytics plugin not enabled"}), 404
    return jsonify(plugin.get_active_sessions()), 200
```

### 1.5 App Integration

**File:** `vbwd-backend/src/app.py` — add plugin loading

```python
# In create_app():
plugin_manager = PluginManager(event_dispatcher)
container.plugin_manager = plugin_manager  # Make available via DI

# Register analytics plugin
from src.plugins.providers.analytics_plugin import AnalyticsPlugin
analytics_plugin = AnalyticsPlugin()
plugin_manager.register_plugin(analytics_plugin)
plugin_manager.initialize_plugin("analytics", {
    "session_count_fn": lambda: Subscription.query.filter_by(status="active").count()
})
plugin_manager.enable_plugin("analytics")

# Register plugin routes
from src.routes.plugins.analytics import analytics_bp
app.register_blueprint(analytics_bp, url_prefix="/api/v1/plugins/analytics")
```

### 1.6 Refactor (if needed)

Only if tests reveal issues. No speculative refactoring.

---

## Phase 2: Admin Frontend Plugin

### 2.1 Unit Tests (RED) — Plugin Definition

**File:** `vbwd-frontend/admin/vue/tests/unit/plugins/analytics-widget.spec.ts`

```
Tests to write FIRST:

test_plugin_has_correct_metadata
  - name == "analytics-widget"
  - version == "1.0.0"

test_plugin_implements_IPlugin_interface
  - has install(), activate(), deactivate() methods  # Liskov

test_plugin_install_registers_component
  - After install(sdk): sdk.getComponents() contains "AnalyticsWidget"

test_plugin_install_registers_store
  - After install(sdk): sdk.getStores() contains "analyticsWidget"

test_plugin_activate_sets_active_flag
  - After activate(): plugin internal state is active

test_plugin_deactivate_clears_active_flag
  - After deactivate(): plugin internal state is inactive

test_plugin_store_fetches_active_sessions
  - Store action fetchActiveSessions() calls GET /plugins/analytics/active-sessions
  - Store state updates with {count, source}

test_plugin_store_handles_api_error
  - When API returns error, store.error is set, count stays 0
```

### 2.2 Implementation (GREEN)

**File:** `vbwd-frontend/admin/vue/src/plugins/analytics-widget/index.ts`

```typescript
// Minimal plugin definition:
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';

export const analyticsWidgetPlugin: IPlugin = {
  name: 'analytics-widget',
  version: '1.0.0',
  description: 'Dashboard analytics widget — active sessions',
  author: 'VBWD Team',

  install(sdk: IPlatformSDK) {
    sdk.addComponent('AnalyticsWidget', () => import('./AnalyticsWidget.vue'));
    sdk.createStore('analyticsWidget', {
      state: () => ({ count: 0, loading: false, error: null as string | null }),
      actions: {
        async fetchActiveSessions() { /* fetch /plugins/analytics/active-sessions */ }
      }
    });
  },

  activate() { this._active = true; },
  deactivate() { this._active = false; }
};
```

**File:** `vbwd-frontend/admin/vue/src/plugins/analytics-widget/AnalyticsWidget.vue`

```vue
<!-- Minimal widget component -->
<template>
  <div class="stat-card plugin-widget" data-testid="analytics-widget">
    <h3>Active Sessions</h3>
    <div class="stat-value" data-testid="active-sessions-count">{{ count }}</div>
    <div class="stat-label">from plugin</div>
  </div>
</template>
```

### 2.3 Runtime Integration — Plugin Loading in Admin App

**File:** `vbwd-frontend/admin/vue/src/main.ts` — add plugin initialization

```typescript
// After pinia + router setup:
import { PluginRegistry, PlatformSDK } from '@vbwd/view-component';
import { analyticsWidgetPlugin } from './plugins/analytics-widget';

const registry = new PluginRegistry();
const sdk = new PlatformSDK();
sdk.api = api;

// Register and install plugins
registry.register(analyticsWidgetPlugin);
await registry.installAll(sdk);
await registry.activate('analytics-widget');

// Add plugin routes to router (if any)
for (const route of sdk.getRoutes()) {
  router.addRoute({ ...route, path: `/admin/${route.path}` });
}

// Make registry available to components
app.provide('pluginRegistry', registry);
app.provide('platformSDK', sdk);
```

### 2.4 Dashboard Integration

**File:** `vbwd-frontend/admin/vue/src/views/Dashboard.vue` — add plugin widget slot

```vue
<!-- After existing stat cards, add plugin widgets section: -->
<div v-if="pluginWidgets.length" class="plugin-widgets">
  <component
    v-for="widget in pluginWidgets"
    :key="widget.name"
    :is="widget.component"
  />
</div>
```

Use `inject('platformSDK')` to get registered components. No over-abstraction — just render what plugins registered.

### 2.5 CLI Validation Tests

**File:** `vbwd-frontend/admin/vue/tests/integration/plugin-cli.spec.ts`

```
Tests to write:

test_plugin_list_shows_analytics_widget
  - Run CLI list command → shows "analytics-widget 1.0.0 REGISTERED"

test_plugin_install_activates_plugin
  - Run CLI install + activate → plugins.json updated with enabled=true

test_plugin_deactivate_disables_plugin
  - Run CLI deactivate → plugins.json updated with enabled=false
```

### 2.6 E2E Test (Playwright)

**File:** `vbwd-frontend/admin/vue/tests/e2e/admin-analytics-plugin.spec.ts`

```
Tests to write FIRST:

test_dashboard_shows_analytics_widget_when_plugin_active
  - Login as admin
  - Navigate to /admin/dashboard
  - Expect element [data-testid="analytics-widget"] to be visible
  - Expect element [data-testid="active-sessions-count"] to contain a number

test_analytics_widget_displays_count_from_api
  - Login as admin
  - Navigate to /admin/dashboard
  - Wait for API response from /plugins/analytics/active-sessions
  - Verify displayed count matches API response

test_dashboard_without_plugin_shows_no_widget
  - (Optional) If plugin is disabled, widget should not render
```

---

## Phase 3: Verification

### 3.1 Backend CLI Verification

```bash
# From vbwd-backend/
make shell
flask plugins list           # Should show: analytics (1.0.0) — ENABLED
flask plugins disable analytics
flask plugins enable analytics
```

Note: Flask CLI commands need to be added as part of this sprint — a simple Click group.

**File:** `vbwd-backend/src/cli/plugins.py`

```python
@app.cli.group()
def plugins():
    """Plugin management commands."""
    pass

@plugins.command()
def list():
    """List all plugins."""
    ...

@plugins.command()
@click.argument("name")
def enable(name):
    """Enable a plugin."""
    ...

@plugins.command()
@click.argument("name")
def disable(name):
    """Disable a plugin."""
    ...
```

### 3.2 Frontend CLI Verification

```bash
# From vbwd-frontend/admin/vue/
npm run plugin list          # Should show: analytics-widget (1.0.0) — ACTIVE
npm run plugin deactivate analytics-widget
npm run plugin activate analytics-widget
```

### 3.3 Full Test Suite

```bash
# Backend
cd vbwd-backend && make test

# Frontend unit
cd vbwd-frontend/admin/vue && npm run test

# Frontend E2E
cd vbwd-frontend/admin/vue && npx playwright test admin-analytics-plugin
```

---

## File Creation Plan

### Backend (new files)

| File | Purpose |
|------|---------|
| `src/plugins/providers/analytics_plugin.py` | AnalyticsPlugin class |
| `src/routes/plugins/__init__.py` | Plugin routes package |
| `src/routes/plugins/analytics.py` | Analytics API endpoint |
| `src/cli/plugins.py` | Flask CLI for plugin management |
| `tests/unit/plugins/test_analytics_plugin.py` | Unit tests |
| `tests/integration/test_analytics_plugin_route.py` | Integration tests |

### Backend (modified files)

| File | Change |
|------|--------|
| `src/app.py` | Register PluginManager, load analytics plugin, register blueprint, register CLI |

### Frontend (new files)

| File | Purpose |
|------|---------|
| `admin/vue/src/plugins/analytics-widget/index.ts` | Plugin definition |
| `admin/vue/src/plugins/analytics-widget/AnalyticsWidget.vue` | Widget component |
| `admin/vue/plugins.json` | Plugin config |
| `admin/vue/tests/unit/plugins/analytics-widget.spec.ts` | Unit tests |
| `admin/vue/tests/integration/plugin-cli.spec.ts` | CLI integration tests |
| `admin/vue/tests/e2e/admin-analytics-plugin.spec.ts` | Playwright E2E |

### Frontend (modified files)

| File | Change |
|------|--------|
| `admin/vue/src/main.ts` | Initialize PluginRegistry, install + activate plugins |
| `admin/vue/src/views/Dashboard.vue` | Add plugin widget rendering slot |

---

## TDD Execution Order

| Step | Type | Description | Status |
|------|------|-------------|--------|
| 1 | Unit (RED) | Write `test_analytics_plugin.py` — all 8 tests fail | [ ] |
| 2 | Code (GREEN) | Implement `analytics_plugin.py` — all 8 tests pass | [ ] |
| 3 | Unit (RED) | Write `test_analytics_plugin_route.py` — 3 tests fail | [ ] |
| 4 | Code (GREEN) | Implement `routes/plugins/analytics.py` + register in `app.py` — tests pass | [ ] |
| 5 | Unit (RED) | Write `analytics-widget.spec.ts` — 8 tests fail | [ ] |
| 6 | Code (GREEN) | Implement `plugins/analytics-widget/` — tests pass | [ ] |
| 7 | Integration | Wire plugin loading in `admin/vue/src/main.ts` | [ ] |
| 8 | Integration | Add widget slot to `Dashboard.vue` | [ ] |
| 9 | CLI (RED) | Write `plugin-cli.spec.ts` — tests fail | [ ] |
| 10 | CLI (GREEN) | Implement `src/cli/plugins.py` (Flask) — tests pass | [ ] |
| 11 | E2E (RED) | Write `admin-analytics-plugin.spec.ts` — tests fail | [ ] |
| 12 | E2E (GREEN) | Fix any integration issues — E2E tests pass | [ ] |
| 13 | Verify | Run full test suite: `make test` + `npm run test` + `npx playwright test` | [ ] |
| 14 | Verify | CLI commands work: `flask plugins list` + `npm run plugin list` | [ ] |

---

## Definition of Done

- [ ] Backend: `AnalyticsPlugin` extends `BasePlugin` (Liskov), managed by `PluginManager`
- [ ] Backend: `GET /api/v1/plugins/analytics/active-sessions` returns data when plugin enabled, 404 when disabled
- [ ] Backend: `flask plugins list/enable/disable` CLI works
- [ ] Backend: 11+ new tests pass (8 unit + 3 integration)
- [ ] Frontend: `analytics-widget` plugin implements `IPlugin` (Liskov), loaded via `PluginRegistry`
- [ ] Frontend: Dashboard shows plugin widget tile with active sessions count
- [ ] Frontend: `npm run plugin list/activate/deactivate` CLI works
- [ ] Frontend: 8+ new unit tests pass
- [ ] Frontend: 2+ new E2E tests pass
- [ ] All existing tests still pass (no regressions)
- [ ] `make pre-commit` passes for backend
- [ ] `./bin/pre-commit-check.sh --admin --unit` passes for frontend
