# Phase 2: Frontend App-as-Library (Factory Extraction)

**Date:** 2026-03-18
**Sprint:** `sprints/01-vbwd-platform-metapackage.md`
**Status:** Done
**Branches:** `feature/platform` (vbwd-fe-user, vbwd-fe-admin)

---

## Summary

Extracted `createVbwdUserApp()` and `createVbwdAdminApp()` factory functions from `main.ts` in both frontend apps. The existing `main.ts` is now a thin wrapper that loads plugins via Vite glob and passes them to the factory. Platform users can import the factory and provide their own plugins.

---

## Changes

### vbwd-fe-user

**New file: `vue/src/factory.ts`**
- Exports `createVbwdUserApp(options)` factory function
- Accepts `{ plugins: IPlugin[], mountSelector?: string }`
- Returns `{ app, router, pinia, registry, sdk, mount }`
- Contains all setup logic: API init, Pinia, Router, i18n, plugin registration, route injection, 404 catch-all

**Updated: `vue/src/main.ts`**
- Reduced from 81 lines to 20 lines
- Loads plugins from local glob via `getEnabledPlugins()`
- Calls `createVbwdUserApp({ plugins })` then `mount()`

### vbwd-fe-admin

**New file: `vue/src/factory.ts`**
- Exports `createVbwdAdminApp(options)` factory function
- Accepts `{ plugins: IPlugin[], adminExtensions?: AdminExtensionMap, mountSelector?: string }`
- Returns `{ app, router, pinia, registry, sdk, mount }`
- Contains all setup: auth store config, EventBus config, Pinia, Router, i18n, plugin registration, extension registry, locale loading from backend

**Updated: `vue/src/main.ts`**
- Reduced from 110 lines to 24 lines
- Loads plugins and admin extensions from local glob
- Calls `createVbwdAdminApp({ plugins, adminExtensions })` then `mount()`

---

## Test Results

### vbwd-fe-user
```
Test Files  46 passed (46)
     Tests  346 passed (346)
     Lint   0 errors, 6 warnings (pre-existing)
```

### vbwd-fe-admin
```
Test Files  23 passed (23)
     Tests  231 passed (231)
     Lint   0 errors, 6 warnings (pre-existing)
```

---

## Platform Usage Pattern

```typescript
// vbwd-platform/fe-user/main.ts
import { createVbwdUserApp } from 'vbwd-fe-user';

const pluginModules = import.meta.glob('./plugins/*/index.ts', { eager: false });

async function bootstrap() {
  const plugins = [];
  for (const [path, loader] of Object.entries(pluginModules)) {
    const mod = await loader();
    const plugin = mod.default ?? Object.values(mod).find(v => v?.install);
    if (plugin) plugins.push(plugin);
  }

  const { mount } = await createVbwdUserApp({ plugins });
  mount('#app');
}

bootstrap();
```
