# Sprint 12 — Plugin System Test Coverage: Error Recovery, Dependencies, Collisions, User App

**Priority:** HIGH
**Goal:** Close the four critical test gaps in the frontend plugin system: error recovery, dependency cascade, resource collision, and user app coverage.

**Principles:** TDD-first, SOLID (SRP, OCP, LSP, ISP, DIP), DRY, Clean Code, Liskov Substitution, No Overengineering

---

## Overview

### Current State

The plugin system has **8 test files** covering happy-path lifecycle, registration, SDK integration, and the analytics-widget plugin. But four categories are untested:

| Gap | Risk | Location |
|-----|------|----------|
| Error recovery | Plugin failures corrupt registry state | `core/tests/` |
| Dependency cascade | Enable/disable chains break silently | `core/tests/` |
| Resource collision | Two plugins overwrite each other's routes/components/stores | `core/tests/` |
| User app | Zero plugin tests, plugin system not wired | `user/vue/tests/` |

### Existing Test Files (for reference, not to be modified)

```
core/tests/unit/plugins/
├── PluginRegistry.spec.ts      # 7 tests — register, validate, metadata
├── PluginLifecycle.spec.ts     # 6 tests — hooks order, status, async, errors
├── PluginDependencies.spec.ts  # 5 tests — topological sort, circular, version constraints
core/tests/integration/
└── plugin-sdk-integration.spec.ts  # 6 tests — routes, components, stores, events

admin/vue/tests/unit/plugins/
├── plugin-bootstrap.spec.ts    # 6 tests — register, install, activate, deactivate
├── analytics-widget.spec.ts    # 15 tests — metadata, lifecycle, component rendering
├── route-injection.spec.ts     # 3 tests — route added, accessible, nested
admin/vue/tests/unit/views/
└── dashboard-plugins.spec.ts   # 3 tests — widget rendering
```

### Target State

Add **4 new test files** with **~45 new tests** covering all four gaps.

---

## Sprint Breakdown

### Sub-sprint 12a: Error Recovery Tests (TDD)

**Goal:** Verify the plugin system handles hook failures gracefully — status remains consistent, other plugins are not affected.

**File:** `vbwd-frontend/core/tests/unit/plugins/PluginErrorRecovery.spec.ts`

**Pattern:** Same imports as `PluginLifecycle.spec.ts` (`PluginRegistry`, `PlatformSDK`, `IPlugin` from `@/plugins/`)

```
Tests to write:

--- Install Failures ---

test_install_error_keeps_status_registered
  - Plugin.install() throws Error("install failed")
  - registry.install('name', sdk) rejects with "install failed"
  - registry.get('name').status === REGISTERED (not INSTALLED)

test_install_error_does_not_affect_other_plugins
  - Plugin A installs successfully
  - Plugin B.install() throws
  - Plugin A status === INSTALLED (unaffected)
  - Plugin B status === REGISTERED

test_install_all_continues_after_single_failure
  - Plugin A (no deps) installs successfully
  - Plugin B (no deps) throws during install
  - Plugin C (no deps) installs successfully
  - A = INSTALLED, B = REGISTERED, C = INSTALLED
  NOTE: installAll() currently throws on first failure (via topological sort loop).
  This test documents current behavior. If installAll() stops on first error,
  verify A is INSTALLED and B is REGISTERED. C may or may not be reached.

--- Activate Failures ---

test_activate_error_keeps_status_installed
  - Plugin installed successfully
  - Plugin.activate() throws Error("activate failed")
  - registry.activate('name') rejects
  - registry.get('name').status === INSTALLED (not ACTIVE or ERROR)

test_activate_error_after_install_allows_retry
  - Plugin installed successfully
  - First activate() throws
  - Fix the plugin (mock returns successfully on second call)
  - Second activate() succeeds
  - Status === ACTIVE

--- Deactivate Failures ---

test_deactivate_error_keeps_status_active
  - Plugin is ACTIVE
  - Plugin.deactivate() throws Error("deactivate failed")
  - registry.deactivate('name') rejects
  - registry.get('name').status === ACTIVE (not INACTIVE)

--- Uninstall Failures ---

test_uninstall_error_keeps_current_status
  - Plugin is INACTIVE (was deactivated)
  - Plugin.uninstall() throws Error("uninstall failed")
  - registry.uninstall('name') rejects
  - registry.get('name').status === INACTIVE (unchanged)

--- Async Errors ---

test_async_install_rejection_handled
  - Plugin.install() returns Promise.reject(new Error("async fail"))
  - registry.install() rejects properly
  - Status === REGISTERED

test_async_activate_rejection_handled
  - Plugin.activate() returns rejected promise
  - registry.activate() rejects properly
  - Status === INSTALLED
```

**Total: 9 tests**

**Implementation notes:**
- These tests only verify existing behavior of `PluginRegistry`. If `installAll()` currently stops on first error, the test documents that (no code change needed).
- If a test reveals that status is NOT properly preserved on error (e.g., status becomes ERROR or undefined), the fix is in `PluginRegistry.ts` — wrap the hook call in try/catch and preserve previous status.
- SRP: This file tests error handling only, not happy-path lifecycle (already in `PluginLifecycle.spec.ts`).

---

### Sub-sprint 12b: Dependency Cascade Tests (TDD)

**Goal:** Verify dependency-aware activate/deactivate behavior — can't activate if deps are inactive, can't deactivate if dependents are active.

**File:** `vbwd-frontend/core/tests/unit/plugins/PluginDependencyCascade.spec.ts`

**Pattern:** Same as `PluginDependencies.spec.ts`

```
Tests to write:

--- Activate with Inactive Dependencies ---

test_activate_fails_if_dependency_not_installed
  - Plugin A depends on Plugin B
  - Both registered, both installed
  - B is NOT activated
  - Activate A → should succeed (current behavior: activate doesn't check deps)
  NOTE: This test documents current behavior. If PluginRegistry
  doesn't check dependency activation status, the test passes as-is.
  We document the design decision.

test_activate_succeeds_when_dependency_is_active
  - Plugin A depends on Plugin B
  - Both installed, B activated first
  - Activate A → succeeds
  - Both ACTIVE

test_install_order_respects_dependencies
  - A depends on B, B depends on C
  - Register in reverse order (A, B, C)
  - installAll() installs in order: C, B, A
  - Verify install hooks called in correct order

--- Deactivate with Active Dependents ---

test_deactivate_when_dependent_is_active
  - Plugin A depends on Plugin B
  - Both installed and ACTIVE
  - Deactivate B (which A depends on) → document current behavior
  NOTE: If PluginRegistry allows deactivating B while A is still active,
  the test documents this. If it throws, test expects the throw.

test_deactivate_independent_plugin_succeeds
  - Plugin A and Plugin B, no dependencies
  - Both installed and ACTIVE
  - Deactivate A → succeeds, B still ACTIVE

--- Uninstall with Dependencies ---

test_uninstall_when_dependent_exists
  - Plugin A depends on Plugin B
  - Both installed, both INACTIVE
  - Uninstall B → document current behavior

--- Complex Dependency Trees ---

test_diamond_dependency_install_order
  - A depends on B and C
  - B depends on D
  - C depends on D
  - installAll() installs D first, then B and C, then A
  - D install hook called exactly once

test_activate_chain_bottom_up
  - A → B → C (dependency chain)
  - Install all
  - Activate C, then B, then A → all ACTIVE

test_deactivate_chain_top_down
  - A → B → C (dependency chain), all ACTIVE
  - Deactivate A, then B, then C → all INACTIVE
  - Reverse order works without errors

test_self_dependency_detected
  - Plugin A depends on itself: dependencies: ['plugin-a']
  - Register A
  - installAll() → throws circular dependency
```

**Total: 10 tests**

**Implementation notes:**
- Some tests may reveal missing behavior (e.g., `deactivate` doesn't check dependents). If so, the fix goes into `PluginRegistry.ts` — add a dependent check in `deactivate()` matching the backend pattern (`PluginManager.disable_plugin()` checks dependents).
- DRY: Reuse the helper pattern from `PluginDependencies.spec.ts` for creating test plugins.
- LSP: Dependency behavior should be consistent with backend `PluginManager` — if backend blocks deactivation when dependents exist, frontend should too.

---

### Sub-sprint 12c: Resource Collision Tests (TDD)

**Goal:** Verify behavior when two plugins register resources with the same name/path/ID.

**File:** `vbwd-frontend/core/tests/unit/plugins/PluginResourceCollision.spec.ts`

**Pattern:** Same as `plugin-sdk-integration.spec.ts` (uses `PlatformSDK` directly)

```
Tests to write:

--- Component Name Collision ---

test_second_component_overwrites_first
  - Plugin A registers component 'SharedWidget'
  - Plugin B registers component 'SharedWidget'
  - sdk.getComponents()['SharedWidget'] === Plugin B's component
  NOTE: Documents current behavior (last-write-wins).

test_component_count_after_collision
  - Plugin A registers 'WidgetA' and 'SharedWidget'
  - Plugin B registers 'WidgetB' and 'SharedWidget'
  - sdk.getComponents() has exactly 3 keys: WidgetA, WidgetB, SharedWidget

--- Route Path Collision ---

test_duplicate_route_path_both_registered
  - Plugin A registers route { path: '/dashboard', name: 'DashA', ... }
  - Plugin B registers route { path: '/dashboard', name: 'DashB', ... }
  - sdk.getRoutes() has 2 entries (both registered, Router handles precedence)

test_duplicate_route_name_both_registered
  - Plugin A registers route { path: '/page-a', name: 'SharedPage', ... }
  - Plugin B registers route { path: '/page-b', name: 'SharedPage', ... }
  - sdk.getRoutes() has 2 entries

--- Store ID Collision ---

test_second_store_overwrites_first
  - Plugin A creates store 'sharedStore' with state { value: 'A' }
  - Plugin B creates store 'sharedStore' with state { value: 'B' }
  - sdk.getStores()['sharedStore'].state().value === 'B'
  NOTE: Documents current behavior (last-write-wins).

test_store_count_after_collision
  - Plugin A creates 'storeA' and 'sharedStore'
  - Plugin B creates 'storeB' and 'sharedStore'
  - sdk.getStores() has exactly 3 keys: storeA, storeB, sharedStore

--- No Collision (Baseline) ---

test_unique_resources_all_preserved
  - Plugin A: component 'WidgetA', route '/page-a', store 'storeA'
  - Plugin B: component 'WidgetB', route '/page-b', store 'storeB'
  - All 6 resources exist independently

--- Cross-Plugin Isolation ---

test_plugins_cannot_read_each_other_stores_during_install
  - Plugin A creates store 'storeA'
  - Plugin B reads sdk.getStores() during install
  - Plugin B can see 'storeA' (SDK state is shared, not isolated per-plugin)
  NOTE: Documents current behavior — SDK is a shared namespace.
```

**Total: 8 tests**

**Implementation notes:**
- These tests primarily **document current behavior** (last-write-wins for components/stores, append for routes). No production code changes expected.
- If we decide collisions should throw (future sprint), these tests become the specification to update.
- OCP: Tests are structured so adding collision-prevention logic later only requires updating expected behavior, not rewriting tests.

---

### Sub-sprint 12d: User App Plugin Bootstrap Tests (TDD)

**Goal:** Test that the plugin system works correctly when bootstrapped in the user app context. The user app has `@vbwd/view-component` as a dependency but hasn't wired up PluginRegistry/PlatformSDK yet.

**File:** `vbwd-frontend/user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts`

**Pattern:** Mirrors `admin/vue/tests/unit/plugins/plugin-bootstrap.spec.ts` exactly (LSP — same plugin system, same test expectations).

```
Tests to write:

--- Core Bootstrap ---

test_registry_and_sdk_instantiate
  - new PluginRegistry() and new PlatformSDK() create valid instances
  - sdk.api and sdk.events are defined

test_register_plugin_in_user_context
  - Create test plugin with name 'user-test-plugin'
  - registry.register(plugin)
  - registry.get('user-test-plugin') returns plugin with status REGISTERED

test_install_registers_component_in_sdk
  - Plugin.install(sdk) calls sdk.addComponent('TestWidget', loader)
  - sdk.getComponents() has 'TestWidget'

test_install_registers_route_in_sdk
  - Plugin.install(sdk) calls sdk.addRoute({ path: '/user-plugin', ... })
  - sdk.getRoutes() has 1 route with path '/user-plugin'

test_install_creates_store_in_sdk
  - Plugin.install(sdk) calls sdk.createStore('userPluginStore', { ... })
  - sdk.getStores() has 'userPluginStore'

test_full_lifecycle_register_install_activate_deactivate
  - Register → install → activate → deactivate
  - Status transitions: REGISTERED → INSTALLED → ACTIVE → INACTIVE

--- User-Specific Scenarios ---

test_multiple_plugins_install_in_dependency_order
  - Plugin A depends on Plugin B
  - installAll(sdk) installs B first, then A

test_plugin_with_no_hooks_installs_successfully
  - Plugin with only name and version (no install/activate/deactivate)
  - register + installAll + activate all succeed

test_install_all_with_empty_registry
  - No plugins registered
  - installAll(sdk) resolves without error
  - sdk.getRoutes() empty, sdk.getComponents() empty

--- Isolation from Admin ---

test_user_and_admin_registries_are_independent
  - Create two separate PluginRegistry instances
  - Register different plugins in each
  - They don't share state

test_user_sdk_state_is_independent
  - Create two PlatformSDK instances
  - Register route in one
  - Other SDK has no routes
```

**Total: 11 tests**

**Implementation notes:**
- The user app already has `@vbwd/view-component` as a dependency (`"file:../core"`), so imports work.
- Tests go in `user/vue/tests/unit/plugins/` (new directory).
- Import pattern: `import { PluginRegistry, PlatformSDK, PluginStatus } from '@vbwd/view-component'` (same as admin).
- DRY: Use a `createTestPlugin()` helper matching the admin pattern.
- These tests prove the plugin system works in user app context without modifying user app production code (main.ts). Wiring up plugins in main.ts is a separate task.
- vitest.config.js already includes `vue/tests/**/*.ts` so the new test file will be picked up automatically.

---

## Testing Approach

### Pre-commit Script

All tests are verified via `bin/pre-commit-check.sh` — the project's standard CI/pre-commit gate.

```bash
# Core plugin tests (12a, 12b, 12c) — run via admin integration (shares core dependency)
./bin/pre-commit-check.sh --admin --integration --no-style

# Admin unit tests (ensure no regressions in existing plugin tests)
./bin/pre-commit-check.sh --admin --unit --no-style

# User plugin tests (12d)
./bin/pre-commit-check.sh --user --unit --no-style

# Full verification — all apps, all test types
./bin/pre-commit-check.sh --admin --user --unit --integration --no-style
```

### How the Script Works

| Flag | What it runs |
|------|-------------|
| `--admin --unit` | `docker-compose run --rm admin-test npx vitest run tests/unit/` |
| `--admin --integration` | `docker-compose run --rm admin-test npx vitest run tests/integration/` |
| `--user --unit` | `docker-compose run --rm user-test npx vitest run vue/tests/unit/` |
| `--no-style` | Skip ESLint + vue-tsc (faster iteration) |
| `--all` | Everything: admin + user, style + unit + integration + e2e |

### Local Quick-Run (without Docker)

```bash
# Core plugin tests (12a, 12b, 12c)
cd vbwd-frontend/core && npx vitest run tests/unit/plugins/

# User plugin tests (12d)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js vue/tests/unit/plugins/

# Admin tests (regression check)
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/plugins/

# All frontend tests
cd vbwd-frontend && make test
```

### Test Discovery

| App | Vitest Config | Pattern |
|-----|---------------|---------|
| Core | `core/vitest.config.ts` | `tests/**/*.spec.ts` (jsdom, `@/` → `src/`) |
| Admin | `admin/vue/vite.config.js` | `tests/unit/**/*.spec.ts`, `tests/integration/**/*.spec.ts` |
| User | `user/vitest.config.js` | `vue/tests/unit/**/*.spec.{js,ts}`, `vue/tests/integration/**/*.spec.{js,ts}` (happy-dom) |

### Import Conventions

| Location | Import from |
|----------|-------------|
| `core/tests/` | `@/plugins/PluginRegistry`, `@/plugins/PlatformSDK`, `@/plugins/types` |
| `admin/vue/tests/` | `@vbwd/view-component` |
| `user/vue/tests/` | `@vbwd/view-component` |

## Verification

### Expected Test Counts After Sprint

| Location | Before | After | Delta |
|----------|--------|-------|-------|
| `core/tests/unit/plugins/` | 18 | 45 | +27 (3 new files) |
| `core/tests/integration/` | 6 | 6 | 0 |
| `admin/vue/tests/unit/plugins/` | 24 | 24 | 0 |
| `user/vue/tests/unit/plugins/` | 0 | 11 | +11 (1 new file) |
| **Total plugin tests** | **48** | **86** | **+38** |

---

## TDD Execution Order

| Step | Type | Sub-sprint | Description | Status |
|------|------|------------|-------------|--------|
| 1 | Tests (RED) | 12a | Write PluginErrorRecovery.spec.ts — 9 tests | [x] PASS (all 9 green out of box) |
| 2 | Fix (GREEN) | 12a | Fix PluginRegistry if status not preserved on error | [x] No fix needed — status preserved by code flow |
| 3 | Verify | 12a | `npx vitest run tests/unit/plugins/PluginErrorRecovery` — green | [x] 9/9 |
| 4 | Tests (RED) | 12b | Write PluginDependencyCascade.spec.ts — 9 tests | [x] 1 RED (deactivate-with-dependents) |
| 5 | Fix (GREEN) | 12b | Add `getActiveDependents()` + dependent check to `deactivate()` | [x] Fixed PluginRegistry.ts |
| 6 | Verify | 12b | `npx vitest run tests/unit/plugins/PluginDependencyCascade` — green | [x] 9/9 |
| 7 | Tests (RED) | 12c | Write PluginResourceCollision.spec.ts — 8 tests | [x] PASS (all 8 green out of box) |
| 8 | Fix (GREEN) | 12c | No fixes expected (documenting behavior) | [x] Confirmed: last-write-wins |
| 9 | Verify | 12c | `npx vitest run tests/unit/plugins/PluginResourceCollision` — green | [x] 8/8 |
| 10 | Tests (RED) | 12d | Write user plugin-bootstrap.spec.ts — 11 tests | [x] PASS (all 11 green out of box) |
| 11 | Fix (GREEN) | 12d | No fixes expected (testing existing core API) | [x] Confirmed |
| 12 | Verify | 12d | `npx vitest run --config vitest.config.js` — green | [x] 11/11 |
| 13 | Verify | ALL | Admin 211/211, User 51/51, Core 36/36 plugin tests — zero regressions | [x] DONE |

---

## File Plan

### New Files

| File | Purpose | Tests | Sub-sprint |
|------|---------|-------|------------|
| `core/tests/unit/plugins/PluginErrorRecovery.spec.ts` | Hook failure handling, status preservation | 9 | 12a |
| `core/tests/unit/plugins/PluginDependencyCascade.spec.ts` | Activate/deactivate with dependency chains | 10 | 12b |
| `core/tests/unit/plugins/PluginResourceCollision.spec.ts` | Component/route/store name collisions | 8 | 12c |
| `user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts` | Plugin system works in user app context | 11 | 12d |

### Modified Files

| File | Change | Sub-sprint |
|------|--------|------------|
| `core/src/plugins/PluginRegistry.ts` | Added `getActiveDependents()` private method + dependent check in `deactivate()` (matches backend `PluginManager.disable_plugin()` pattern) | 12b |

### NOT Modified (confirmed by tests)

| File | Why |
|------|-----|
| `core/src/plugins/PluginRegistry.ts` (12a) | Status already preserved on error — error throws before status update line executes |

### Files NOT Modified

- No changes to `PlatformSDK.ts` (collision tests document current behavior)
- No changes to user app production code (main.ts, vite.config.js, tsconfig.json)
- No changes to admin app code or tests

---

## Definition of Done

- [x] 9 error recovery tests pass — status preserved on install/activate/deactivate/uninstall failures
- [x] 9 dependency cascade tests pass — activate/deactivate respect dependency chains
- [x] 8 resource collision tests pass — behavior documented for component/route/store name conflicts
- [x] 11 user app plugin tests pass — plugin system works in user context
- [x] All existing plugin tests still pass (36 core + 24 admin = 60, no regressions)
- [x] All existing frontend tests pass (admin 211/211, user 51/51)
- [x] PluginRegistry.ts fix: 1 change — added `getActiveDependents()` + check in `deactivate()`

---

## Principles Applied

| Principle | Application |
|-----------|-------------|
| **TDD** | Write all tests first (RED), then fix only what fails (GREEN) |
| **SRP** | Each test file covers exactly one concern: errors, deps, collisions, user bootstrap |
| **OCP** | Tests document current behavior — if we add collision prevention later, only expectations change |
| **LSP** | User app plugin-bootstrap.spec.ts mirrors admin's exactly — same plugin system, same contract |
| **ISP** | Tests only import what they need (`PluginRegistry`, `PlatformSDK`, `IPlugin`) |
| **DIP** | Tests depend on `IPlugin` interface, not concrete plugin implementations |
| **DRY** | `createTestPlugin()` helper reused across tests. Same import pattern as existing files. |
| **Liskov** | Frontend deactivate-with-dependents behavior should match backend `PluginManager.disable_plugin()` |
| **Clean Code** | Descriptive test names explain the scenario. Each test tests one thing. |
| **No Overengineering** | No abstract test base classes. No test factories. No custom matchers. Plain vitest assertions. |
