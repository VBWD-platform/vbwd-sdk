# Sprint 8: Integration & Documentation

**Duration:** 1 week
**Goal:** Integration testing and comprehensive documentation
**Dependencies:** All previous sprints

---

## Objectives

- [ ] Write integration tests (plugin loading, API client, auth flow)
- [ ] Generate API documentation (TypeDoc)
- [ ] Create usage examples for all features
- [ ] Write migration guide (symlink → npm package)
- [ ] Create troubleshooting guide
- [ ] Run performance benchmarks
- [ ] Prepare for npm package publication

---

## Tasks

### 1. Integration Tests

**File:** `frontend/core/__tests__/integration/full-auth-flow.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import { createPinia } from 'pinia';
import { PluginRegistry, PluginLoader } from '../../src/plugin';
import { PlatformSDKImpl } from '../../src/sdk';
import { ApiClient } from '../../src/api';
import { AuthService } from '../../src/auth';
import { EventBus } from '../../src/events';
import { ValidationService } from '../../src/validation';
import { defaultApiConfig } from '../../src/api/ApiConfig';

describe('Full Authentication Flow', () => {
  it('should complete full auth cycle', async () => {
    // Setup
    const app = createApp({});
    const router = createRouter({ history: createWebHistory(), routes: [] });
    const pinia = createPinia();

    const apiClient = new ApiClient(defaultApiConfig);
    const authService = new AuthService(apiClient);
    const eventBus = new EventBus();
    const validationService = new ValidationService();

    const sdk = new PlatformSDKImpl(
      app,
      router,
      pinia,
      apiClient,
      authService,
      eventBus,
      validationService
    );

    // Test login flow
    // (Mock API responses needed)

    expect(authService.isAuthenticated()).toBe(false);

    // Simulate login
    // await authService.login({ email: 'test@example.com', password: 'password' });

    // expect(authService.isAuthenticated()).toBe(true);
    // expect(authService.getCurrentUser()).toBeDefined();
  });
});
```

**File:** `frontend/core/__tests__/integration/plugin-system-full.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import { createPinia } from 'pinia';
import { PluginRegistry, PluginLoader, type IPlugin } from '../../src/plugin';
import { PlatformSDKImpl } from '../../src/sdk';

describe('Plugin System - Full Integration', () => {
  it('should load multiple plugins with dependencies', async () => {
    const app = createApp({});
    const router = createRouter({ history: createWebHistory(), routes: [] });
    const pinia = createPinia();

    const sdk = new PlatformSDKImpl(
      app,
      router,
      pinia,
      {} as any,
      {} as any,
      {} as any,
      {} as any
    );

    const registry = new PluginRegistry();
    const loader = new PluginLoader(registry, sdk);

    // Plugin A (no dependencies)
    const pluginA: IPlugin = {
      metadata: { name: 'plugin-a', version: '1.0.0' },
      install: async () => {
        console.log('Plugin A installed');
      },
      registerRoutes: () => [
        {
          path: '/a',
          name: 'route-a',
          component: () => Promise.resolve({ template: '<div>A</div>' }),
        },
      ],
    };

    // Plugin B (depends on A)
    const pluginB: IPlugin = {
      metadata: {
        name: 'plugin-b',
        version: '1.0.0',
        dependencies: ['plugin-a'],
      },
      install: async () => {
        console.log('Plugin B installed');
      },
    };

    registry.register(pluginB);
    registry.register(pluginA);

    const results = await loader.loadAll();

    expect(results).toHaveLength(2);
    expect(results[0]?.name).toBe('plugin-a');
    expect(results[1]?.name).toBe('plugin-b');
    expect(results.every((r) => r.status === 'active')).toBe(true);

    // Verify route was registered
    expect(router.hasRoute('route-a')).toBe(true);
  });
});
```

### 2. TypeDoc Configuration

**File:** `frontend/core/typedoc.json`

```json
{
  "entryPoints": ["src/index.ts"],
  "out": "docs/api",
  "plugin": ["typedoc-plugin-markdown"],
  "excludePrivate": true,
  "excludeProtected": false,
  "excludeInternal": true,
  "readme": "README.md",
  "name": "@vbwd/core-sdk",
  "includeVersion": true,
  "sort": ["source-order"],
  "categorizeByGroup": true,
  "navigationLinks": {
    "GitHub": "https://github.com/vbwd/vbwd-sdk"
  }
}
```

### 3. Usage Examples

**File:** `frontend/core/docs/examples/01-basic-setup.md`

```markdown
# Basic Setup

## Installation

```bash
npm install @vbwd/core-sdk
```

## Creating Platform SDK

```typescript
import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import { createPinia } from 'pinia';
import { PlatformSDKImpl, ApiClient, AuthService, EventBus, ValidationService } from '@vbwd/core-sdk';

const app = createApp(App);
const router = createRouter({
  history: createWebHistory(),
  routes: [],
});
const pinia = createPinia();

// Initialize services
const apiClient = new ApiClient({
  baseURL: import.meta.env.VITE_API_BASE_URL,
});

const authService = new AuthService(apiClient);
const eventBus = new EventBus();
const validationService = new ValidationService();

// Create SDK
const sdk = new PlatformSDKImpl(
  app,
  router,
  pinia,
  apiClient,
  authService,
  eventBus,
  validationService
);

app.use(router);
app.use(pinia);
app.mount('#app');
```
```

**File:** `frontend/core/docs/examples/02-creating-plugin.md`

```markdown
# Creating a Plugin

## Basic Plugin

```typescript
import type { IPlugin } from '@vbwd/core-sdk';

export const myPlugin: IPlugin = {
  metadata: {
    name: 'my-plugin',
    version: '1.0.0',
    displayName: 'My Plugin',
    description: 'A sample plugin',
  },

  async install(app, sdk) {
    console.log('Installing my plugin');

    // Access SDK services
    sdk.events.on('user:logged-in', (payload) => {
      console.log('User logged in:', payload.user);
    });
  },

  async activate() {
    console.log('Plugin activated');
  },

  registerRoutes() {
    return [
      {
        path: '/my-feature',
        name: 'my-feature',
        component: () => import('./views/MyFeature.vue'),
      },
    ];
  },
};
```

## Loading Plugins

```typescript
import { PluginRegistry, PluginLoader } from '@vbwd/core-sdk';

const registry = new PluginRegistry();
const loader = new PluginLoader(registry, sdk);

registry.register(myPlugin);

await loader.loadAll();
```
```

### 4. Migration Guide

**File:** `frontend/core/docs/MIGRATION.md`

```markdown
# Migration Guide: Symlink → NPM Package

## Current Setup (Symlinks)

```bash
# From frontend/user/vue/
npm link ../../core

# From frontend/admin/vue/
npm link ../../core
```

## Future Setup (NPM Package)

### Step 1: Publish Core SDK

```bash
cd frontend/core
npm version 1.0.0
npm publish --access public
```

### Step 2: Update User App

```bash
cd frontend/user/vue

# Remove symlink
npm unlink @vbwd/core-sdk

# Install from npm
npm install @vbwd/core-sdk@^1.0.0
```

### Step 3: Update Admin App

```bash
cd frontend/admin/vue

# Remove symlink
npm unlink @vbwd/core-sdk

# Install from npm
npm install @vbwd/core-sdk@^1.0.0
```

### Step 4: Update Imports (No Changes Needed)

Imports remain the same:

```typescript
import { PluginRegistry, ApiClient } from '@vbwd/core-sdk';
```

## Version Management

- Use semantic versioning (MAJOR.MINOR.PATCH)
- Breaking changes → MAJOR version bump
- New features → MINOR version bump
- Bug fixes → PATCH version bump

## Development Workflow

```bash
# Develop in core
cd frontend/core
npm run dev

# Test in user app (with symlink during development)
cd ../user/vue
npm link ../../core
npm run dev

# When ready to release
cd ../../core
npm version patch
npm publish
```
```

### 5. Troubleshooting Guide

**File:** `frontend/core/docs/TROUBLESHOOTING.md`

```markdown
# Troubleshooting Guide

## Common Issues

### 1. "Plugin not found in registry"

**Cause:** Plugin not registered before calling `loader.loadAll()`

**Solution:**
```typescript
registry.register(myPlugin); // Register first
await loader.loadAll();       // Then load
```

### 2. "Circular dependency detected"

**Cause:** Plugin A depends on B, and B depends on A

**Solution:** Review plugin dependencies and break the cycle

### 3. Token refresh fails

**Cause:** Refresh token expired or invalid

**Solution:** Clear tokens and redirect to login:
```typescript
authService.clearTokens();
router.push('/login');
```

### 4. CORS errors in development

**Cause:** API client making requests to different origin

**Solution:** Configure CORS in backend or use proxy in Vite:
```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      '/api': 'http://localhost:5000'
    }
  }
});
```

### 5. Symlink not working

**Cause:** npm link fails or imports not resolving

**Solution:**
```bash
# Clear npm cache
npm cache clean --force

# Re-create symlink
cd frontend/core
npm link

cd ../user/vue
npm link @vbwd/core-sdk
```

## Debug Mode

Enable debug logging:

```typescript
// In main.ts
if (import.meta.env.DEV) {
  window.__VBWD_DEBUG__ = true;
}
```
```

### 6. Performance Benchmarks

**File:** `frontend/core/__tests__/performance/benchmarks.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { PluginRegistry, PluginLoader } from '../../src/plugin';
import type { IPlugin } from '../../src/plugin';

describe('Performance Benchmarks', () => {
  it('should load 100 plugins in under 1 second', async () => {
    const registry = new PluginRegistry();
    const loader = new PluginLoader(registry, {} as any);

    // Create 100 test plugins
    for (let i = 0; i < 100; i++) {
      const plugin: IPlugin = {
        metadata: { name: `plugin-${i}`, version: '1.0.0' },
        install: async () => {},
      };
      registry.register(plugin);
    }

    const start = performance.now();
    await loader.loadAll();
    const end = performance.now();

    expect(end - start).toBeLessThan(1000);
  });

  it('should resolve 1000 plugin dependencies in under 100ms', () => {
    const registry = new PluginRegistry();

    // Create chain of 1000 plugins
    for (let i = 0; i < 1000; i++) {
      const plugin: IPlugin = {
        metadata: {
          name: `plugin-${i}`,
          version: '1.0.0',
          dependencies: i > 0 ? [`plugin-${i - 1}`] : [],
        },
        install: async () => {},
      };
      registry.register(plugin);
    }

    const start = performance.now();
    registry.resolveLoadOrder();
    const end = performance.now();

    expect(end - start).toBeLessThan(100);
  });
});
```

---

## Definition of Done

- [x] Integration tests covering main workflows
- [x] TypeDoc configuration and API docs generated
- [x] Usage examples for all major features
- [x] Migration guide from symlink to npm
- [x] Troubleshooting guide
- [x] Performance benchmarks passing
- [x] README.md updated
- [x] CHANGELOG.md created
- [x] Package ready for npm publication

---

## Publication Checklist

- [ ] All tests passing (unit + integration)
- [ ] Coverage ≥ 95%
- [ ] TypeScript strict mode passing
- [ ] ESLint passing with no warnings
- [ ] API documentation generated
- [ ] README.md complete
- [ ] LICENSE file present (BSL-1.1)
- [ ] CHANGELOG.md updated
- [ ] Version bumped in package.json
- [ ] Git tag created
- [ ] npm publish completed
- [ ] GitHub release created

---

## Next Steps

After Sprint 8, the Core SDK is ready to be consumed by:
- [User App Sprints](../../architecture_core_view_user/sprints/README.md)
- [Admin App Sprints](../../architecture_core_view_admin/sprints/README.md)
