> **Status:** COMPLETED (code implemented, tests passing)
> **Completed:** 2026-02-07

# Sprint 06 — Frontend PluginRegistry Init + Dynamic Route Injection

**Priority:** HIGH
**Goal:** Initialize `PluginRegistry` and `PlatformSDK` in admin `main.ts`. Replace direct widget import with proper plugin lifecycle. Inject plugin routes into Vue Router at runtime.

**Principles:** TDD-first, SOLID, DRY, Liskov Substitution, DI, Clean Code, No Overengineering

---

## Overview

The admin app already has:
- `@vbwd/view-component` with `PluginRegistry`, `PlatformSDK`, `IPlugin` (built + tested)
- `analytics-widget` plugin in `src/plugins/analytics-widget/` implementing `IPlugin`
- Dashboard with `<AnalyticsWidget />` hard-imported

This sprint:
1. Initialize `PluginRegistry` + `PlatformSDK` in `main.ts`
2. Load analytics-widget via registry instead of direct import
3. Dashboard reads widgets from SDK instead of hard import
4. Plugin routes injected into Vue Router via `router.addRoute()`

No new plugin is created. We're wiring existing infrastructure.

---

## Phase 1: Plugin Bootstrap in main.ts

### 1.1 Unit Tests (RED)

**File:** `admin/vue/tests/unit/plugins/plugin-bootstrap.spec.ts`

```
Tests to write FIRST:

test_plugin_registry_registers_analytics_widget
  - Create registry, register analyticsWidgetPlugin
  - registry.getPlugin("analytics-widget") is defined

test_plugin_install_registers_component_in_sdk
  - Create registry + sdk, install plugin
  - sdk.getComponents() has "AnalyticsWidget"

test_plugin_activate_sets_active_status
  - install + activate
  - registry.getMetadata("analytics-widget").status == "ACTIVE"

test_sdk_provides_api_client
  - Create sdk, set api
  - sdk.api is the api instance

test_plugin_routes_collected_in_sdk
  - If plugin registers routes via sdk.addRoute(), sdk.getRoutes() returns them

test_plugin_deactivate_changes_status
  - activate then deactivate
  - status == "INACTIVE"
```

### 1.2 Implementation (GREEN)

**File:** `admin/vue/src/main.ts` — add plugin initialization

Current state (lines 30-35):
```typescript
const app = createApp(App);
const pinia = createPinia();
app.use(pinia);
app.use(router);
app.use(i18n);
```

Change to:
```typescript
import { PluginRegistry, PlatformSDK } from '@vbwd/view-component';
import { analyticsWidgetPlugin } from './plugins/analytics-widget';

const app = createApp(App);
const pinia = createPinia();
app.use(pinia);
app.use(router);
app.use(i18n);

// Initialize plugin system
const registry = new PluginRegistry();
const sdk = new PlatformSDK();

registry.register(analyticsWidgetPlugin);
await registry.installAll(sdk);
await registry.activate('analytics-widget');

// Inject plugin routes into Vue Router
for (const route of sdk.getRoutes()) {
  router.addRoute('admin', { ...route, path: route.path });
}

// Make available to components via provide/inject
app.provide('pluginRegistry', registry);
app.provide('platformSDK', sdk);
```

**Note:** `main.ts` needs to become async. Wrap mount in an async IIFE or top-level await (Vite supports it).

Key decisions:
- **DI:** SDK and registry injected via `app.provide()`, consumed with `inject()` — no global singletons
- **Liskov:** analytics-widget is loaded exactly like any future plugin — no special treatment
- **No overengineering:** No plugin config file yet, no dynamic discovery — just explicit `registry.register()` calls

---

## Phase 2: Dashboard Reads Widgets from SDK

### 2.1 Unit Tests (RED)

**File:** `admin/vue/tests/unit/views/dashboard-plugins.spec.ts`

```
Tests to write FIRST:

test_dashboard_renders_plugin_widgets_from_sdk
  - Provide platformSDK with AnalyticsWidget component registered
  - Mount Dashboard
  - Expect [data-testid="analytics-widget"] visible

test_dashboard_renders_no_widgets_when_sdk_empty
  - Provide platformSDK with no components
  - Mount Dashboard
  - Expect .plugin-widgets section empty or hidden

test_dashboard_renders_multiple_plugin_widgets
  - Register 2 mock components in SDK
  - Mount Dashboard
  - Both render in .plugin-widgets
```

### 2.2 Implementation (GREEN)

**File:** `admin/vue/src/views/Dashboard.vue`

Replace:
```typescript
import AnalyticsWidget from '../plugins/analytics-widget/AnalyticsWidget.vue'
```

With:
```typescript
import { inject, computed, defineAsyncComponent } from 'vue'
import type { PlatformSDK } from '@vbwd/view-component'

const sdk = inject<PlatformSDK>('platformSDK')
const pluginWidgets = computed(() => {
  if (!sdk) return []
  const components = sdk.getComponents()
  return Object.entries(components).map(([name, loader]) => ({
    name,
    component: defineAsyncComponent(loader as () => Promise<any>)
  }))
})
```

Template change:
```vue
<!-- Replace static <AnalyticsWidget /> with dynamic rendering -->
<div v-if="pluginWidgets.length" class="plugin-widgets">
  <component
    v-for="widget in pluginWidgets"
    :key="widget.name"
    :is="widget.component"
  />
</div>
```

Key decisions:
- **OCP:** Dashboard is now open for extension (new plugins add widgets) without modification
- **DI:** SDK injected via `inject()`, not imported directly
- **No overengineering:** No widget registration API, no slot system — just render what SDK has

---

## Phase 3: Route Injection Validation

### 3.1 Unit Tests (RED)

**File:** `admin/vue/tests/unit/plugins/route-injection.spec.ts`

```
Tests to write FIRST:

test_plugin_route_added_to_router
  - Create router with base routes
  - Register plugin that adds route via sdk.addRoute({ path: 'test-page', ... })
  - Call router.addRoute() with SDK routes
  - router.hasRoute('test-page') == true

test_plugin_route_is_accessible
  - After injection, router.resolve({ name: 'test-page' }) succeeds

test_plugin_route_inherits_admin_layout
  - Injected route is child of /admin parent
  - Route has requiresAuth meta from parent
```

### 3.2 Implementation

Already done in Phase 1 (`main.ts` loop). The analytics-widget doesn't register routes currently, but the mechanism is ready. To validate, we add a trivial test route in the analytics-widget plugin's `install()`:

**File:** `admin/vue/src/plugins/analytics-widget/index.ts` — optional addition:

```typescript
install(sdk: IPlatformSDK): void {
  sdk.addComponent('AnalyticsWidget', () => import('./AnalyticsWidget.vue') as Promise<{ default: unknown }>)
  // No routes needed for a widget-only plugin — route injection tested separately
}
```

No change needed if the plugin has no routes. The test uses a mock plugin to verify the mechanism works.

---

## Phase 4: Verification

### 4.1 Run All Tests

```bash
# Admin unit tests (includes new + existing)
cd vbwd-frontend/admin/vue && npx vitest run

# User unit tests (no regressions)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# TypeScript check
cd vbwd-frontend/admin/vue && npx vue-tsc --noEmit
```

### 4.2 Rebuild & Manual Check

```bash
cd vbwd-frontend && docker compose up -d --build admin-app
# Navigate to http://localhost:8081/admin/dashboard
# Verify analytics widget still renders
```

---

## File Plan

### New Files

| File | Purpose |
|------|---------|
| `admin/vue/tests/unit/plugins/plugin-bootstrap.spec.ts` | Registry + SDK init tests |
| `admin/vue/tests/unit/views/dashboard-plugins.spec.ts` | Dashboard dynamic widget tests |
| `admin/vue/tests/unit/plugins/route-injection.spec.ts` | Route injection tests |

### Modified Files

| File | Change |
|------|--------|
| `admin/vue/src/main.ts` | Add PluginRegistry + PlatformSDK init, async bootstrap |
| `admin/vue/src/views/Dashboard.vue` | Replace hard import with `inject('platformSDK')` dynamic widgets |

---

## TDD Execution Order

| Step | Type | Description | Status |
|------|------|-------------|--------|
| 1 | Unit (RED) | Write `plugin-bootstrap.spec.ts` — 6 tests fail | [ ] |
| 2 | Code (GREEN) | Update `main.ts` with registry + sdk init — tests pass | [ ] |
| 3 | Unit (RED) | Write `dashboard-plugins.spec.ts` — 3 tests fail | [ ] |
| 4 | Code (GREEN) | Update `Dashboard.vue` with dynamic widgets — tests pass | [ ] |
| 5 | Unit (RED) | Write `route-injection.spec.ts` — 3 tests fail | [ ] |
| 6 | Code (GREEN) | Route injection already in main.ts — verify tests pass | [ ] |
| 7 | Verify | Run full frontend test suite — no regressions | [ ] |
| 8 | Verify | TypeScript check passes | [ ] |
| 9 | Verify | Rebuild container, manual check widget renders | [ ] |

---

## Definition of Done

- [ ] `PluginRegistry` and `PlatformSDK` initialized in `main.ts`
- [ ] `analytics-widget` loaded via registry lifecycle (register -> install -> activate)
- [ ] Dashboard renders widgets from SDK (no direct plugin imports)
- [ ] Plugin routes injected into Vue Router via `router.addRoute()`
- [ ] Registry and SDK available via `inject()` in any component
- [ ] 12+ new unit tests pass
- [ ] All existing tests pass (no regressions)
- [ ] TypeScript check passes
- [ ] Admin container rebuilt and widget visible at `/admin/dashboard`
