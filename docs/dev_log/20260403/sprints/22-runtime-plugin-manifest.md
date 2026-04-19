# Sprint 22 — Runtime Plugin Manifest Loading

**Status:** Planned
**Date:** 2026-04-19
**Principles:** TDD-first · SOLID · DRY · Config-only deployment
**Repos affected:** `vbwd-fe-user`, `vbwd-fe-admin`, `vbwd-fe-core`

---

## Problem

Both `vbwd-fe-user` and `vbwd-fe-admin` import `plugins.json` at **build time**:

```typescript
// pluginLoader.ts (line 2 in both repos)
import pluginsManifest from '@plugins/plugins.json';
```

This bakes the enabled/disabled state into the JavaScript bundle. For multi-instance deployment (Sprint 21), we need **runtime** plugin manifest loading so that mounting a different `plugins.json` via Docker volume actually changes which plugins are active — without rebuilding the image.

Same issue with `config.json` in fe-admin `stores/plugins.ts`:

```typescript
import savedConfigs from '@plugins/config.json';
```

---

## Goal

Replace all build-time `import ... from '@plugins/plugins.json'` and `import ... from '@plugins/config.json'` with runtime `fetch()` calls. Both fe-user and fe-admin should use the **same** `fetchPluginManifest()` utility from `vbwd-fe-core`, ensuring consistent behavior across apps.

### Key Constraint

The `import.meta.glob()` for plugin **code** stays as-is — Vite must know all plugin entry points at build time. Only the **manifest** (which plugins to activate) and **config** (runtime settings) move to runtime loading.

---

## Architecture

```
Build time (stays the same):
  import.meta.glob('../../../plugins/*/index.ts')  → discovers all plugin code
  import.meta.glob('@plugins/*/config.json')       → discovers all config schemas

Runtime (NEW):
  fetch('/plugins.json')  → which plugins to activate
  fetch('/config.json')   → saved plugin configs

Docker mount:
  ./fe-user/plugins.json:/usr/share/nginx/html/plugins.json:ro
  ./fe-admin/plugins.json:/usr/share/nginx/html/plugins.json:ro
```

### Files Changed

| File | Change |
|------|--------|
| `vbwd-fe-core/src/plugins/manifest.ts` | **NEW** — `fetchPluginManifest()`, `fetchPluginConfig()` |
| `vbwd-fe-core/src/plugins/types.ts` | Add `PluginManifest`, `PluginManifestEntry` types |
| `vbwd-fe-core/src/plugins/index.ts` | Export new types + functions |
| `vbwd-fe-user/vue/src/utils/pluginLoader.ts` | Replace `import` with `await fetchPluginManifest()` |
| `vbwd-fe-admin/vue/src/utils/pluginLoader.ts` | Replace `import` with `await fetchPluginManifest()` |
| `vbwd-fe-admin/vue/src/stores/plugins.ts` | Replace `import pluginsRegistry/savedConfigs` with runtime fetch |

---

## Detailed Design

### 22a — `PluginManifest` types in `vbwd-fe-core`

**File:** `vbwd-fe-core/src/plugins/types.ts`

```typescript
export interface PluginManifestEntry {
  enabled: boolean;
  version: string;
  installedAt?: string;
  source: string;
}

export interface PluginManifest {
  plugins: Record<string, PluginManifestEntry>;
}
```

### 22b — `fetchPluginManifest()` in `vbwd-fe-core`

**File:** `vbwd-fe-core/src/plugins/manifest.ts`

```typescript
import type { PluginManifest } from './types';

const DEFAULT_MANIFEST_PATH = '/plugins.json';
const DEFAULT_CONFIG_PATH = '/config.json';

/**
 * Fetch the plugin manifest at runtime.
 * Falls back to the build-time baked manifest if fetch fails
 * (e.g., dev server without a mounted file).
 */
export async function fetchPluginManifest(
  path: string = DEFAULT_MANIFEST_PATH,
  fallback?: PluginManifest,
): Promise<PluginManifest> {
  try {
    const response = await fetch(path);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const data = await response.json();
    // Validate shape
    if (!data || typeof data !== 'object' || !data.plugins) {
      throw new Error('Invalid manifest: missing "plugins" key');
    }
    return data as PluginManifest;
  } catch (error) {
    console.warn(
      `[PluginManifest] Failed to fetch ${path}, using fallback:`,
      error,
    );
    if (fallback) return fallback;
    return { plugins: {} };
  }
}

/**
 * Fetch saved plugin configs at runtime.
 */
export async function fetchPluginConfigs(
  path: string = DEFAULT_CONFIG_PATH,
): Promise<Record<string, Record<string, unknown>>> {
  try {
    const response = await fetch(path);
    if (!response.ok) return {};
    return await response.json();
  } catch {
    return {};
  }
}
```

**Design decisions:**
- Fallback parameter allows dev mode to pass the build-time manifest when fetch fails (dev server doesn't serve `/plugins.json` from public/)
- Returns empty `{ plugins: {} }` on total failure — app works, just no plugins
- No caching — manifest is fetched once at startup

### 22c — Update `pluginLoader.ts` in `vbwd-fe-user`

**Before:**
```typescript
import pluginsManifest from '@plugins/plugins.json';
// ...
const manifest: PluginManifest = pluginsManifest as PluginManifest;
```

**After:**
```typescript
import { fetchPluginManifest } from 'vbwd-view-component';
import type { PluginManifest } from 'vbwd-view-component';
import buildTimeManifest from '@plugins/plugins.json';

// ...
export async function getEnabledPlugins(): Promise<IPlugin[]> {
  const manifest = await fetchPluginManifest('/plugins.json', buildTimeManifest as PluginManifest);
  // ... rest stays the same
}
```

The build-time import remains as fallback for dev mode (no mounted file). In production Docker, the mounted `/plugins.json` takes precedence.

### 22d — Update `pluginLoader.ts` in `vbwd-fe-admin`

Same pattern as 22c. The `getEnabledPluginNames()` function also needs the manifest:

```typescript
let cachedManifest: PluginManifest | null = null;

export async function getEnabledPlugins(): Promise<IPlugin[]> {
  cachedManifest = await fetchPluginManifest('/plugins.json', buildTimeManifest as PluginManifest);
  // ... load enabled plugins from cachedManifest
}

export function getEnabledPluginNames(): Set<string> {
  if (!cachedManifest) {
    // Sync fallback: use build-time manifest
    const manifest = buildTimeManifest as PluginManifest;
    return new Set(Object.entries(manifest.plugins).filter(([, c]) => c.enabled).map(([n]) => n));
  }
  return new Set(Object.entries(cachedManifest.plugins).filter(([, c]) => c.enabled).map(([n]) => n));
}
```

### 22e — Update `stores/plugins.ts` in `vbwd-fe-admin`

Replace the two build-time imports:

**Before (line 2-3):**
```typescript
import pluginsRegistry from '@plugins/plugins.json';
import savedConfigs from '@plugins/config.json';
```

**After:**
```typescript
import { fetchPluginManifest, fetchPluginConfigs } from 'vbwd-view-component';
import type { PluginManifest } from 'vbwd-view-component';
import buildTimeRegistry from '@plugins/plugins.json';
import buildTimeConfigs from '@plugins/config.json';

let registry: PluginManifest = buildTimeRegistry as PluginManifest;
let configs: Record<string, Record<string, unknown>> = buildTimeConfigs as Record<string, Record<string, unknown>>;
let manifestLoaded = false;

async function ensureManifestLoaded(): Promise<void> {
  if (manifestLoaded) return;
  registry = await fetchPluginManifest('/plugins.json', buildTimeRegistry as PluginManifest);
  configs = await fetchPluginConfigs('/config.json');
  manifestLoaded = true;
}
```

Then each store action calls `await ensureManifestLoaded()` before accessing `registry`/`configs`.

### 22f — Copy `plugins.json` to `public/` in both apps

Both apps need `plugins.json` served as a static file for dev mode:

- `vbwd-fe-user/vue/public/plugins.json` — already exists (just keep in sync)
- `vbwd-fe-admin/vue/public/plugins.json` — **NEW** (copy from `plugins/plugins.json`)
- `vbwd-fe-admin/vue/public/config.json` — **NEW** (copy from `plugins/config.json`)

Add a Vite plugin or npm script to auto-copy these on build if desired.

---

## Test Plan (TDD-first)

### Unit Tests — `vbwd-fe-core`

**File:** `vbwd-fe-core/tests/unit/plugins/manifest.spec.ts`

```
describe('fetchPluginManifest')
  ✓ fetches and parses valid manifest from URL
  ✓ returns fallback when fetch returns 404
  ✓ returns fallback when fetch throws network error
  ✓ returns empty manifest when no fallback provided and fetch fails
  ✓ rejects manifest without "plugins" key (returns fallback)
  ✓ rejects non-object response (returns fallback)
  ✓ handles manifest with zero plugins
  ✓ handles manifest with mixed enabled/disabled plugins

describe('fetchPluginConfigs')
  ✓ fetches and parses valid config from URL
  ✓ returns empty object on 404
  ✓ returns empty object on network error
  ✓ returns empty object on invalid JSON
```

### Unit Tests — `vbwd-fe-user`

**File:** `vbwd-fe-user/vue/tests/unit/utils/pluginLoader-runtime.spec.ts`

```
describe('getEnabledPlugins (runtime manifest)')
  ✓ fetches manifest at runtime, not from build-time import
  ✓ loads only plugins with enabled: true from runtime manifest
  ✓ skips plugins with enabled: false in runtime manifest
  ✓ falls back to build-time manifest when fetch fails
  ✓ returns empty array when both runtime and fallback have no plugins
  ✓ handles plugin module not found (logged, skipped)
  ✓ handles plugin with no IPlugin export (logged, skipped)

describe('getEnabledPluginNames (runtime manifest)')
  ✓ returns Set of enabled plugin names from runtime manifest
  ✓ uses build-time fallback when manifest not yet loaded
```

### Unit Tests — `vbwd-fe-admin`

**File:** `vbwd-fe-admin/vue/tests/unit/utils/pluginLoader-runtime.spec.ts`

```
describe('getEnabledPlugins (runtime manifest)')
  ✓ fetches manifest at runtime
  ✓ caches manifest for getEnabledPluginNames()
  ✓ falls back to build-time manifest on fetch failure
  ✓ localStorage override still takes precedence over runtime manifest

describe('getEnabledPluginNames')
  ✓ returns names from cached runtime manifest
  ✓ returns names from build-time manifest before first load
```

**File:** `vbwd-fe-admin/vue/tests/unit/stores/plugins-runtime.spec.ts`

```
describe('Plugins Store (runtime manifest)')
  ✓ fetchPlugins loads registry from runtime manifest, not build-time import
  ✓ fetchPluginDetail reads config from runtime config.json
  ✓ fetchPlugins falls back to build-time manifest on fetch failure
  ✓ savePluginConfig updates in-memory configs
  ✓ activatePlugin persists to localStorage
  ✓ deactivatePlugin persists to localStorage
```

### Integration Test — Docker Mount Override

**File:** `vbwd-fe-user/vue/tests/integration/runtime-manifest.spec.ts`

Manual/CI test (not unit — requires built app):

```
describe('Runtime manifest override via Docker mount')
  ✓ App with mounted plugins.json (3 plugins) loads exactly 3 plugins
  ✓ App with mounted plugins.json (0 plugins) loads zero plugins
  ✓ App without mounted plugins.json uses build-time manifest (all plugins)
```

This can be tested via Playwright against a Docker container with a custom mount.

---

## Sub-Sprint Order

| # | Task | Repo | Test Count | Effort |
|---|------|------|------------|--------|
| 22a | Add `PluginManifest` types to fe-core | vbwd-fe-core | 0 (types only) | 15 min |
| 22b | Implement `fetchPluginManifest()` + `fetchPluginConfigs()` in fe-core | vbwd-fe-core | 12 tests | 45 min |
| 22c | Update pluginLoader.ts in fe-user (runtime fetch + fallback) | vbwd-fe-user | 9 tests | 30 min |
| 22d | Update pluginLoader.ts in fe-admin (runtime fetch + fallback + cache) | vbwd-fe-admin | 6 tests | 30 min |
| 22e | Update stores/plugins.ts in fe-admin (runtime registry + configs) | vbwd-fe-admin | 6 tests | 45 min |
| 22f | Add plugins.json + config.json to public/ dirs, update Dockerfiles | both | 0 | 15 min |
| 22g | CI: run all existing tests (no regressions) | all 3 repos | existing | 15 min |
| **Total** | | | **~33 new tests** | **~3.5 hours** |

---

## Implementation Notes

### Backward Compatibility

- Build-time manifest import stays as fallback → dev mode (`npm run dev`) works exactly as before
- `import.meta.glob` for plugin code is unchanged → all plugins are still in the bundle
- Only the **activation gate** moves to runtime
- The `localStorage` override in fe-admin (`vbwd_admin_plugin_state`) continues to take highest precedence

### Precedence Order (highest to lowest)

1. `localStorage` override (`vbwd_admin_plugin_state`) — fe-admin only
2. Runtime `/plugins.json` (mounted via Docker volume)
3. Build-time `@plugins/plugins.json` (fallback)

### Docker Mount Points

```yaml
# docker-compose.instance.yml volumes:
fe-user:
  volumes:
    - ./fe-user/plugins.json:/usr/share/nginx/html/plugins.json:ro
    - ./fe-user/config.json:/usr/share/nginx/html/config.json:ro

fe-admin:
  volumes:
    - ./fe-admin/plugins.json:/usr/share/nginx/html/plugins.json:ro
    - ./fe-admin/config.json:/usr/share/nginx/html/config.json:ro
```

### Why Not Fetch from Backend API?

The manifest fetch is a static JSON file, not an API call to the backend. Reasons:
- No auth needed (public static file)
- No CORS issues (same origin)
- Works before the app is fully initialized
- No dependency on backend being healthy at frontend load time
- nginx serves it with zero latency

---

## Not in Scope

- Plugin **hot-reload** (enable/disable without page refresh)
- Backend API for frontend plugin management (admin can toggle via API later)
- Per-plugin `config.json` runtime fetch (schemas stay build-time via `import.meta.glob`)
- Plugin code splitting per instance (all code stays in bundle; only activation changes)
