# Sprint 25a Report — Frontend Static Analysis & Test Fixes

**Date:** 2026-02-12
**Status:** DONE
**Priority:** CRITICAL

---

## Summary

Fixed all frontend static analysis issues and test stderr noise across the admin app. Eliminated 3 categories of warnings (missing i18n keys, incomplete test routers, double Pinia instantiation), upgraded `@typescript-eslint` from v6 to v8 to support TypeScript 5.9.3, and fixed Docker test container module resolution for the admin plugins directory.

---

## Fix 1: Missing i18n Keys (3 sources)

### 1a. `users.roles` used as label — UserDetails.vue
**Problem:** `$t('users.roles')` used as a `<label>` text, but `users.roles` is an object (`{ user, admin, vendor }`), not a string. Vue-i18n emits a "not a string" warning.

**Fix:** Added `users.rolesLabel` key ("Roles" / "Rollen") to both `en.json` and `de.json`. Changed `UserDetails.vue:82` from `$t('users.roles')` to `$t('users.rolesLabel')`.

### 1b. `subscriptions.statuses.canceled` — SubscriptionDetails.vue
**Problem:** Status badge builds key dynamically from subscription status value `'canceled'` (American spelling), but i18n only had `'cancelled'` (British spelling). Missing key warning on every canceled subscription render.

**Fix:** Added `subscriptions.statuses.canceled` ("Canceled" / "Storniert") to both locale files, alongside existing `cancelled`.

### 1c. `plugins.detail.*` wrong namespace — PluginDetails.vue
**Problem:** Three `t()` calls used `plugins.detail.configSaved`, `plugins.detail.confirmDeactivate`, `plugins.detail.confirmUninstall` — but keys live at `adminPlugins.detail.*`. Missing key warnings on save/deactivate/uninstall actions.

**Fix:** Changed 3 occurrences in `PluginDetails.vue` from `plugins.detail.*` to `adminPlugins.detail.*`.

### Files changed
- `admin/vue/src/i18n/locales/en.json` — +2 keys
- `admin/vue/src/i18n/locales/de.json` — +2 keys
- `admin/vue/src/views/UserDetails.vue` — 1 line
- `admin/vue/src/views/PluginDetails.vue` — 3 lines

---

## Fix 2: Vue Router "No match found" Warnings (8 test files)

### 2a. AdminLayout.spec.ts — missing sidebar routes
**Problem:** Test router only had 6 routes but the AdminLayout sidebar renders links to 11 routes. Vue Router warned for every missing route on every render.

**Fix:** Added 5 missing stub routes: `/admin/add-ons`, `/admin/subscriptions`, `/admin/invoices`, `/admin/settings`, `/admin/payment-methods`.

### 2b. Empty path warnings in 7 integration tests
**Problem:** `createMemoryHistory()` starts at `/`. Tests that don't explicitly navigate before mounting trigger "No match found for location with path /" since no route handles `/`.

**Fix:** Added `{ path: '/', redirect: '/admin/...' }` root catch-all to each test router.

### 2c. Missing `/edit` routes in Plans.spec.ts and Users.spec.ts
**Problem:** Plan and user row clicks navigate to `/:id/edit` but test routers only defined `/:id`. Vue Router warned about unmatched edit paths.

**Fix:** Added `/:id/edit` routes to both test files.

### Files changed
- `admin/vue/tests/integration/AdminLayout.spec.ts`
- `admin/vue/tests/integration/Subscriptions.spec.ts`
- `admin/vue/tests/integration/Users.spec.ts`
- `admin/vue/tests/integration/Plans.spec.ts`
- `admin/vue/tests/integration/Invoices.spec.ts`
- `admin/vue/tests/integration/Settings.spec.ts`
- `admin/vue/tests/integration/Login.spec.ts`

---

## Fix 3: Double Pinia "App already provides" Warning

**Problem:** `tests/setup.ts` registered pinia as a global plugin (`config.global.plugins = [i18n, pinia]`). Tests that also pass pinia in `mount()` options caused Vue to warn about duplicate app-level pinia injection.

**Fix:** Removed pinia from `setup.ts` global plugins. Each test already calls `setActivePinia(createPinia())` in `beforeEach`, and Pinia's `useStore()` falls back to the active pinia when no app-level pinia is injected.

### Files changed
- `admin/vue/tests/setup.ts` — removed pinia import and global plugin registration

---

## Fix 4: TypeScript-ESLint Version Warning

**Problem:** `@typescript-eslint/typescript-estree` v6.21.0 only supports TypeScript <5.4.0. Project uses TypeScript 5.9.3, producing a noisy warning on every ESLint run and test execution.

**Fix:** Upgraded `@typescript-eslint/parser` and `@typescript-eslint/eslint-plugin` from v6.21.0 to v8.55.0 in `admin/vue`. v8 supports TypeScript >=4.7.4 <5.10.0. Also fixed one new lint error caught by v8's stricter `no-unused-vars` rule (removed unused `e` in `Login.vue` catch block).

### Files changed
- `admin/vue/package.json` — `@typescript-eslint/*` v6 → v8
- `admin/vue/src/views/Login.vue` — `catch (e)` → `catch`

---

## Fix 5: Docker Admin Test Container — Plugin Module Resolution

**Problem:** The `admin-test` Docker service mounts `./admin/vue:/app` but not the sibling `admin/plugins/` directory. From inside the container, all plugin imports (`@plugins/*`, `../../../plugins/*.json`) resolve to `/plugins/` which doesn't exist. This causes TS2307 errors and Vite "Failed to resolve import" failures.

**Root cause:** `docker-compose.yaml` `admin-test` and `admin-dev` volume mounts incomplete.

**Fix (two parts):**

1. **docker-compose.yaml** — Added `./admin/plugins:/plugins` volume mount to both `admin-test` and `admin-dev` services. From workdir `/app`, `../plugins` resolves to `/plugins` which now contains the mounted plugin files.

2. **Replace fragile relative paths with `@plugins` alias** — Changed all deep relative imports in source code:
   - `src/main.ts`: `../../plugins/plugins.json` → `@plugins/plugins.json`
   - `src/stores/plugins.ts`: `../../../plugins/plugins.json` → `@plugins/plugins.json`
   - `src/stores/plugins.ts`: `../../../plugins/config.json` → `@plugins/config.json`
   - `src/stores/plugins.ts`: 3 `import.meta.glob('../../../plugins/...')` → `import.meta.glob('@plugins/...')`

The `@plugins` alias is defined in both `vite.config.js` and `tsconfig.json` paths, resolving to `../plugins/` relative to project root.

### Files changed
- `docker-compose.yaml` — 2 volume mounts added
- `admin/vue/src/main.ts` — 1 import path
- `admin/vue/src/stores/plugins.ts` — 5 import paths

---

## Test Results

| Suite | Tests | Status |
|-------|-------|--------|
| Admin unit + integration | 331 | passing |
| Admin ESLint | 0 errors | clean |
| Admin vue-tsc | 0 errors | clean |
| Admin stderr | 0 warnings | clean |

---

## Files Modified Summary

| File | Change |
|------|--------|
| `admin/vue/src/i18n/locales/en.json` | +`users.rolesLabel`, +`subscriptions.statuses.canceled` |
| `admin/vue/src/i18n/locales/de.json` | +`users.rolesLabel`, +`subscriptions.statuses.canceled` |
| `admin/vue/src/views/UserDetails.vue` | `$t('users.roles')` → `$t('users.rolesLabel')` |
| `admin/vue/src/views/PluginDetails.vue` | `plugins.detail.*` → `adminPlugins.detail.*` (3x) |
| `admin/vue/src/views/Login.vue` | `catch (e)` → `catch` |
| `admin/vue/src/main.ts` | Plugin import via `@plugins` alias |
| `admin/vue/src/stores/plugins.ts` | All plugin imports via `@plugins` alias |
| `admin/vue/tests/setup.ts` | Remove pinia from global plugins |
| `admin/vue/tests/integration/AdminLayout.spec.ts` | +5 routes, +root redirect |
| `admin/vue/tests/integration/Subscriptions.spec.ts` | +root redirect |
| `admin/vue/tests/integration/Users.spec.ts` | +root redirect, +edit route |
| `admin/vue/tests/integration/Plans.spec.ts` | +root redirect, +edit route |
| `admin/vue/tests/integration/Invoices.spec.ts` | +root redirect |
| `admin/vue/tests/integration/Settings.spec.ts` | +root redirect |
| `admin/vue/tests/integration/Login.spec.ts` | +root redirect |
| `admin/vue/package.json` | `@typescript-eslint/*` v6 → v8 |
| `docker-compose.yaml` | +plugins volume for admin-test, admin-dev |
