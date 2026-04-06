# Sprint 02 — CMS Slug Routing Fix

**Date:** 2026-03-05
**Status:** In Progress
**Refs:** Report `01-cms-pages.md` (Sprint 01 — CMS Pages Plugin complete)

---

## Goal

`http://localhost:8080/test` must render the published CMS page with slug `test`.

---

## Bug Analysis

### Bug 1 — Plugin system silently broken (ALL plugins affected)

**File:** `vbwd-fe-user/vue/src/utils/pluginLoader.ts:57`

```ts
const plugin: IPlugin = pluginModule.default;   // ← expects default export
if (!plugin) {
  console.warn(`[PluginRegistry] Plugin '${pluginName}' has no default export. Skipping.`);
  continue;
}
```

**Reality:** Every plugin in `vbwd-fe-user/plugins/*/index.ts` uses a **named export**:

| Plugin | Export |
|--------|--------|
| `landing1` | `export const landing1Plugin` |
| `checkout` | `export const checkoutPlugin` |
| `stripe-payment` | `export const stripePaymentPlugin` |
| `paypal-payment` | `export const paypalPaymentPlugin` |
| `yookassa-payment` | `export const yookassaPaymentPlugin` |
| `theme-switcher` | `export const themeSwitcherPlugin` |
| `chat` | `export const chatPlugin` |
| `taro` | `export const taroPlugin` |
| `cms` | `export const cmsPlugin` |

`pluginModule.default` is `undefined` for all of them → **all 9 plugins are silently skipped at boot**.

**Fix:** Update `pluginLoader.ts` to resolve the IPlugin object from any named export when `default` is absent. Detection rule: the object has an `install` method (IPlugin contract). DRY — one fix, no need to touch 9 plugin files.

### Bug 2 — CMS route registered as `/page/:slug` instead of `/:slug`

**File:** `vbwd-fe-user/plugins/cms/index.ts:11`

```ts
sdk.addRoute({
  path: '/page/:slug',  // ← wrong — produces /page/test, not /test
  ...
});
```

The page slug stored in the backend is `test` (no leading slash). The API call resolves correctly: `GET /api/v1/cms/pages/test`. But the Vue Router route must be `/:slug` so that `/test` in the browser maps to `route.params.slug = "test"`.

Vue Router 4 gives static segments (e.g. `/login`, `/dashboard`) higher priority than parameters (`/:slug`), so registering `/:slug` as a plugin route is safe — it will never shadow existing static routes regardless of registration order.

---

## Changes

### 1. `vbwd-fe-user/vue/src/utils/pluginLoader.ts`

Update `getEnabledPlugins()` to fall back to the first named export that satisfies the IPlugin contract when `default` is absent.

```ts
// Before
const plugin: IPlugin = pluginModule.default;

// After
const plugin: IPlugin =
  pluginModule.default ??
  (Object.values(pluginModule) as unknown[]).find(
    (v): v is IPlugin => !!v && typeof v === 'object' && typeof (v as IPlugin).install === 'function'
  );
```

This is backward-compatible: default exports are still preferred; named exports are used as a fallback.

### 2. `vbwd-fe-user/plugins/cms/index.ts`

Change route path from `/page/:slug` to `/:slug`.

```ts
// Before
path: '/page/:slug',
name: 'cms-page',

// After
path: '/:slug',
name: 'cms-page',
```

---

## Tests

### New test file: `vbwd-fe-user/vue/tests/unit/plugins/cms-plugin.spec.ts`

Tests for:
1. `cmsPlugin` registers `/:slug` route (not `/page/:slug`)
2. `cmsPlugin` registers `/pages` route
3. `cmsPlugin` installs without error
4. `/:slug` CMS route resolves correctly; static routes take priority over it

### New test file: `vbwd-fe-user/vue/tests/unit/utils/pluginLoader-named-export.spec.ts`

Tests for:
1. Plugin with named export is loaded (not skipped)
2. Plugin with default export is loaded (backward compat)
3. Plugin with no IPlugin-shaped export is skipped with warning
4. Module with multiple exports: correct IPlugin is identified by `install` method

---

## Acceptance Criteria

- [ ] `http://localhost:8080/test` renders the CMS page with slug `test`
- [ ] All 9 existing plugins load (no "has no default export" warnings in console)
- [ ] CMS plugin registers route `/:slug`, not `/page/:slug`
- [ ] Static routes (`/login`, `/dashboard`, etc.) are NOT shadowed by `/:slug`
- [ ] New unit tests pass
- [ ] Full unit test suite passes: `npm run test`
- [ ] Lint passes: `npm run lint`

---

## SOLID / Architecture notes

- **Single Responsibility:** `pluginLoader.ts` only concern is resolving plugin instances from modules — the fix keeps that boundary clean
- **Open/Closed:** No plugin files need to change; loader handles both export styles
- **Liskov:** IPlugin contract (presence of `install`) is used as the discriminant — any valid plugin satisfies it
- **DRY:** One change fixes the root cause for all 9 plugins
- **Core agnostic:** Only `pluginLoader.ts` (infrastructure) is modified — no business-logic plugin files touched

---

## Files modified

| File | Change |
|------|--------|
| `vbwd-fe-user/vue/src/utils/pluginLoader.ts` | Fallback to named IPlugin export |
| `vbwd-fe-user/plugins/cms/index.ts` | Route path `/:slug` |
| `vbwd-fe-user/vue/tests/unit/plugins/cms-plugin.spec.ts` | New — CMS plugin route tests |
| `vbwd-fe-user/vue/tests/unit/utils/pluginLoader-named-export.spec.ts` | New — loader named-export tests |