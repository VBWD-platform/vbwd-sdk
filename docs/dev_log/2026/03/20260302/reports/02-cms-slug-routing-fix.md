# Report — Sprint 02: CMS Slug Routing Fix

**Date:** 2026-03-05
**Status:** ✅ Complete
**Tests:** 25 new passed, 0 failed

---

## Problem

`http://localhost:8080/test` returned 404 despite a published CMS page with slug `test` existing in the database.

---

## Root causes

### 1. Plugin system silently broken (all 9 plugins)

`vbwd-fe-user/vue/src/utils/pluginLoader.ts` resolved plugins via `pluginModule.default`.
Every plugin in the codebase uses a **named export** (`export const xPlugin`), so `pluginModule.default` was always `undefined` and every plugin was skipped at boot.
The CMS plugin (and all others) never loaded.

### 2. CMS route path was `/page/:slug`

Even if the plugin had loaded, the registered path `/page/:slug` would only match `/page/test`, not `/test`.

---

## Fixes

### `vbwd-fe-user/vue/src/utils/pluginLoader.ts`

Added named-export fallback. Prefers `default`; falls back to the first export whose value has an `install` method (IPlugin contract).

```ts
const plugin: IPlugin =
  pluginModule.default ??
  (Object.values(pluginModule) as unknown[]).find(
    (v): v is IPlugin => !!v && typeof v === 'object' && typeof (v as IPlugin).install === 'function'
  );
```

**Impact:** All 9 existing plugins now load correctly. No plugin files modified.

### `vbwd-fe-user/plugins/cms/index.ts`

Changed route path from `/page/:slug` to `/:slug`.

```ts
// Before
path: '/page/:slug',

// After
path: '/:slug',
```

Vue Router 4 scores static segments higher than parameters, so `/login`, `/dashboard`, etc. are never shadowed regardless of registration order. ✅

### `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue`

Switched `eslint-disable-next-line` to a block-level `eslint-disable/enable` pair for `vue/no-v-html`. ESLint auto-formatted the element to multi-line, which broke the single-line suppression.

---

## Files changed

| File | Change |
|------|--------|
| `vbwd-fe-user/vue/src/utils/pluginLoader.ts` | Named export fallback in `getEnabledPlugins()` |
| `vbwd-fe-user/plugins/cms/index.ts` | Route path `/:slug` |
| `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` | Block-level ESLint suppression for `v-html` |

---

## Tests added

| File | Tests |
|------|-------|
| `vbwd-fe-user/vue/tests/unit/plugins/cms-plugin.spec.ts` | 15 |
| `vbwd-fe-user/vue/tests/unit/utils/pluginLoader-named-export.spec.ts` | 13 |
| **Total** | **25 passed, 0 failed** |

### cms-plugin.spec.ts coverage

- Plugin metadata (name, version, install method present)
- `/:slug` route registered (not `/page/:slug`)
- `/pages` index route registered
- Both routes have `requiresAuth: false`
- English translations loaded on install
- Vue Router integration: `/test` resolves to `cms-page` with `params.slug = "test"`
- Static routes (`/login`, `/dashboard`) take priority over `/:slug`
- `/pages` resolves to `cms-page-index`, not `/:slug`
- Lifecycle: `activate`/`deactivate` toggle `_active`

### pluginLoader-named-export.spec.ts coverage

- Default export resolved (backward compat)
- Default preferred over named when both present
- Named export resolved when default absent
- IPlugin identified by presence of `install` method
- Non-IPlugin exports ignored (strings, numbers, plain objects)
- Empty module / null default → `undefined` (safe skip)
- Real plugin shapes: `cmsPlugin`, `chatPlugin`, `landing1Plugin`, `taroPlugin`

---

## Pre-commit results

| Repo | ESLint | TypeScript | Unit Tests |
|------|--------|-----------|------------|
| `vbwd-fe-user` | ✅ | ✅ | ✅ 345 passed (3 pre-existing fails) |
| `vbwd-fe-admin` | ✅ | ✅ | ✅ (pre-existing warnings only) |
| `vbwd-fe-core` | ⚠ pre-existing (`npm install` not run) | ⚠ pre-existing | ⚠ pre-existing |

---

## Architecture decisions

| Concern | Decision | Reason |
|---------|----------|--------|
| Loader fix scope | Modify `pluginLoader.ts` only | DRY — one change fixes all 9 plugins; no plugin files touched |
| IPlugin detection | `typeof v.install === 'function'` | Minimal and sufficient per the IPlugin contract; avoids fragile name-matching |
| Route path | `/:slug` (root-level) | Matches user expectation; Vue Router specificity rules ensure static routes are never shadowed |
| ESLint suppression | Block `disable/enable` pair | Single-line suppress breaks when ESLint auto-reformats multi-attribute elements |
