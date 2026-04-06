# Sprint 1: Plugin System (TDD with Vitest)

**Duration**: 1 week (5 days)
**Status**: 📋 Ready After Sprint 0
**Dependencies**: Sprint 0 (Foundation)
**Testing**: Unit & Integration Tests (Vitest)

---

## Goal

Implement extensible plugin architecture allowing user and admin applications to dynamically load features.

## Testing Strategy

**REMINDER**: Core SDK is a library - use **unit and integration tests only**:
- ✅ **Unit Tests**: Test PluginRegistry, PluginLoader, validation logic
- ✅ **Integration Tests**: Test plugin lifecycle with PlatformSDK
- ❌ **E2E Tests**: NOT applicable for SDK (only for apps built on SDK)

## TDD Workflow

### Day 1: Write Tests
Write all unit and integration tests BEFORE implementation.

### Day 2: Implement Interfaces & Types
Create TypeScript interfaces to pass type-checking.

### Day 3-4: Implement Core Logic
Build Plugin Registry, PluginLoader, and PlatformSDK.

### Day 5: Refactor & Document
Clean up, add JSDoc, write usage examples.

---

## Unit Test Scenarios (Write First!)

### 1. Plugin Registration Tests

```typescript
// tests/unit/plugins/PluginRegistry.spec.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { PluginRegistry } from '@/plugins/PluginRegistry';
import type { IPlugin } from '@/plugins/types';

describe('PluginRegistry', () => {
  let registry: PluginRegistry;

  beforeEach(() => {
    registry = new PluginRegistry();
  });

  it('should register a simple plugin', () => {
    const plugin: IPlugin = {
      name: 'test-plugin',
      version: '1.0.0',
      description: 'A test plugin'
    };

    registry.register(plugin);
    const retrieved = registry.get('test-plugin');

    expect(retrieved).toBeDefined();
    expect(retrieved?.name).toBe('test-plugin');
    expect(retrieved?.version).toBe('1.0.0');
    expect(retrieved?.status).toBe('REGISTERED');
  });

  it('should prevent duplicate plugin names', () => {
    const plugin1: IPlugin = { name: 'duplicate', version: '1.0.0' };
    const plugin2: IPlugin = { name: 'duplicate', version: '2.0.0' };

    registry.register(plugin1);

    expect(() => registry.register(plugin2)).toThrow(
      'Plugin "duplicate" is already registered'
    );
  });

  it('should validate required plugin fields', () => {
    expect(() => registry.register({} as IPlugin)).toThrow('Plugin name is required');

    expect(() => registry.register({ name: 'test' } as IPlugin)).toThrow(
      'Plugin version is required'
    );
  });

  it('should validate semver version format', () => {
    const invalidPlugin: IPlugin = { name: 'test', version: 'invalid' };

    expect(() => registry.register(invalidPlugin)).toThrow('Invalid version format');
  });

  it('should store plugin metadata', () => {
    const plugin: IPlugin = {
      name: 'rich-plugin',
      version: '1.0.0',
      description: 'A plugin with metadata',
      author: 'VBWD Team',
      homepage: 'https://example.com',
      keywords: ['test', 'example']
    };

    registry.register(plugin);
    const retrieved = registry.get('rich-plugin');

    expect(retrieved?.description).toBe('A plugin with metadata');
    expect(retrieved?.author).toBe('VBWD Team');
    expect(retrieved?.keywords).toEqual(['test', 'example']);
  });

  it('should return all registered plugins', () => {
    registry.register({ name: 'plugin-a', version: '1.0.0' });
    registry.register({ name: 'plugin-b', version: '2.0.0' });

    const all = registry.getAll();

    expect(all).toHaveLength(2);
    expect(all.map(p => p.name)).toContain('plugin-a');
    expect(all.map(p => p.name)).toContain('plugin-b');
  });

  it('should return undefined for non-existent plugin', () => {
    const result = registry.get('non-existent');
    expect(result).toBeUndefined();
  });
});
```

### 2. Plugin Lifecycle Tests

```typescript
// tests/unit/plugins/PluginLifecycle.spec.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { PluginRegistry } from '@/plugins/PluginRegistry';
import { PlatformSDK } from '@/plugins/PlatformSDK';
import type { IPlugin } from '@/plugins/types';

describe('Plugin Lifecycle', () => {
  let registry: PluginRegistry;
  let sdk: PlatformSDK;

  beforeEach(() => {
    registry = new PluginRegistry();
    sdk = new PlatformSDK();
  });

  it('should execute lifecycle hooks in correct order', async () => {
    const calls: string[] = [];

    const plugin: IPlugin = {
      name: 'lifecycle-test',
      version: '1.0.0',
      install(sdk) {
        calls.push('install');
      },
      activate() {
        calls.push('activate');
      },
      deactivate() {
        calls.push('deactivate');
      },
      uninstall() {
        calls.push('uninstall');
      }
    };

    registry.register(plugin);
    await registry.install('lifecycle-test', sdk);
    await registry.activate('lifecycle-test');
    await registry.deactivate('lifecycle-test');
    await registry.uninstall('lifecycle-test');

    expect(calls).toEqual(['install', 'activate', 'deactivate', 'uninstall']);
  });

  it('should track plugin status through lifecycle', async () => {
    const plugin: IPlugin = {
      name: 'status-test',
      version: '1.0.0',
      install() {},
      activate() {},
      deactivate() {}
    };

    registry.register(plugin);
    expect(registry.get('status-test')?.status).toBe('REGISTERED');

    await registry.install('status-test', sdk);
    expect(registry.get('status-test')?.status).toBe('INSTALLED');

    await registry.activate('status-test');
    expect(registry.get('status-test')?.status).toBe('ACTIVE');

    await registry.deactivate('status-test');
    expect(registry.get('status-test')?.status).toBe('INACTIVE');
  });

  it('should handle async lifecycle hooks', async () => {
    let asyncCompleted = false;

    const plugin: IPlugin = {
      name: 'async-test',
      version: '1.0.0',
      install() {},
      async activate() {
        await new Promise(resolve => setTimeout(resolve, 10));
        asyncCompleted = true;
      }
    };

    registry.register(plugin);
    await registry.install('async-test', sdk);
    await registry.activate('async-test');

    expect(asyncCompleted).toBe(true);
  });

  it('should propagate errors from lifecycle hooks', async () => {
    const plugin: IPlugin = {
      name: 'error-test',
      version: '1.0.0',
      install() {},
      activate() {
        throw new Error('Activation failed');
      }
    };

    registry.register(plugin);
    await registry.install('error-test', sdk);

    await expect(registry.activate('error-test')).rejects.toThrow('Activation failed');
  });

  it('should not activate plugin without installing first', async () => {
    const plugin: IPlugin = {
      name: 'test',
      version: '1.0.0',
      activate() {}
    };

    registry.register(plugin);

    await expect(registry.activate('test')).rejects.toThrow(
      'Plugin must be installed before activation'
    );
  });

  it('should allow multiple activate/deactivate cycles', async () => {
    const calls: string[] = [];

    const plugin: IPlugin = {
      name: 'cycle-test',
      version: '1.0.0',
      install() {},
      activate() {
        calls.push('activate');
      },
      deactivate() {
        calls.push('deactivate');
      }
    };

    registry.register(plugin);
    await registry.install('cycle-test', sdk);

    await registry.activate('cycle-test');
    await registry.deactivate('cycle-test');
    await registry.activate('cycle-test');
    await registry.deactivate('cycle-test');

    expect(calls).toEqual(['activate', 'deactivate', 'activate', 'deactivate']);
  });
});
```

### 3. Plugin Dependency Tests

```typescript
// tests/unit/plugins/PluginDependencies.spec.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { PluginRegistry } from '@/plugins/PluginRegistry';
import { PlatformSDK } from '@/plugins/PlatformSDK';
import type { IPlugin } from '@/plugins/types';

describe('Plugin Dependencies', () => {
  let registry: PluginRegistry;
  let sdk: PlatformSDK;

  beforeEach(() => {
    registry = new PluginRegistry();
    sdk = new PlatformSDK();
  });

  it('should load plugins in dependency order', async () => {
    const installed: string[] = [];

    const pluginA: IPlugin = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: ['plugin-b', 'plugin-c'],
      install() {
        installed.push('a');
      }
    };

    const pluginB: IPlugin = {
      name: 'plugin-b',
      version: '1.0.0',
      dependencies: ['plugin-c'],
      install() {
        installed.push('b');
      }
    };

    const pluginC: IPlugin = {
      name: 'plugin-c',
      version: '1.0.0',
      install() {
        installed.push('c');
      }
    };

    registry.register(pluginA);
    registry.register(pluginB);
    registry.register(pluginC);

    await registry.installAll(sdk);

    // C first (no deps), then B (depends on C), then A (depends on B and C)
    expect(installed).toEqual(['c', 'b', 'a']);
  });

  it('should detect circular dependencies', async () => {
    const pluginA: IPlugin = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: ['plugin-b']
    };

    const pluginB: IPlugin = {
      name: 'plugin-b',
      version: '1.0.0',
      dependencies: ['plugin-c']
    };

    const pluginC: IPlugin = {
      name: 'plugin-c',
      version: '1.0.0',
      dependencies: ['plugin-a'] // Circular!
    };

    registry.register(pluginA);
    registry.register(pluginB);
    registry.register(pluginC);

    await expect(registry.installAll(sdk)).rejects.toThrow('Circular dependency detected');
  });

  it('should fail if dependency is missing', async () => {
    const plugin: IPlugin = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: ['missing-plugin']
    };

    registry.register(plugin);

    await expect(registry.installAll(sdk)).rejects.toThrow(
      'Dependency "missing-plugin" not found'
    );
  });

  it('should support version constraints', async () => {
    const pluginA: IPlugin = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: { 'plugin-b': '^2.0.0' }
    };

    const pluginB: IPlugin = {
      name: 'plugin-b',
      version: '2.5.0'
    };

    registry.register(pluginA);
    registry.register(pluginB);

    await expect(registry.installAll(sdk)).resolves.not.toThrow();
  });

  it('should fail if version constraint not met', async () => {
    const pluginA: IPlugin = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: { 'plugin-b': '^2.0.0' }
    };

    const pluginB: IPlugin = {
      name: 'plugin-b',
      version: '1.5.0' // Does not satisfy ^2.0.0
    };

    registry.register(pluginA);
    registry.register(pluginB);

    await expect(registry.installAll(sdk)).rejects.toThrow(
      'Plugin "plugin-b" version 1.5.0 does not satisfy ^2.0.0'
    );
  });
});
```

---

## Integration Test Scenarios

### 4. Plugin + PlatformSDK Integration Tests

```typescript
// tests/integration/plugin-sdk-integration.spec.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { PluginRegistry } from '@/plugins/PluginRegistry';
import { PlatformSDK } from '@/plugins/PlatformSDK';
import type { IPlugin, IPlatformSDK } from '@/plugins/types';

describe('Plugin + PlatformSDK Integration', () => {
  let registry: PluginRegistry;
  let sdk: PlatformSDK;

  beforeEach(() => {
    registry = new PluginRegistry();
    sdk = new PlatformSDK();
  });

  it('should provide API client to plugins', async () => {
    let receivedApi: any = null;

    const plugin: IPlugin = {
      name: 'api-test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        receivedApi = sdk.api;
      }
    };

    registry.register(plugin);
    await registry.install('api-test', sdk);

    expect(receivedApi).toBeDefined();
    expect(receivedApi).toBe(sdk.api);
  });

  it('should allow plugins to register routes', async () => {
    const plugin: IPlugin = {
      name: 'route-test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        sdk.addRoute({
          path: '/plugin-page',
          name: 'PluginPage',
          component: () => import('./PluginPage.vue')
        });
      }
    };

    registry.register(plugin);
    await registry.install('route-test', sdk);

    const routes = sdk.getRoutes();
    expect(routes).toHaveLength(1);
    expect(routes[0].path).toBe('/plugin-page');
    expect(routes[0].name).toBe('PluginPage');
  });

  it('should allow plugins to register components', async () => {
    const plugin: IPlugin = {
      name: 'component-test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        sdk.addComponent('MyComponent', () => import('./MyComponent.vue'));
      }
    };

    registry.register(plugin);
    await registry.install('component-test', sdk);

    const components = sdk.getComponents();
    expect(components).toHaveProperty('MyComponent');
    expect(typeof components.MyComponent).toBe('function');
  });

  it('should provide event bus to plugins', async () => {
    let receivedEvents: any = null;

    const plugin: IPlugin = {
      name: 'event-test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        receivedEvents = sdk.events;
      }
    };

    registry.register(plugin);
    await registry.install('event-test', sdk);

    expect(receivedEvents).toBeDefined();
    expect(receivedEvents).toBe(sdk.events);
  });

  it('should allow plugins to create stores', async () => {
    const plugin: IPlugin = {
      name: 'store-test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        sdk.createStore('pluginStore', {
          state: () => ({ count: 0 }),
          actions: {
            increment() {
              this.count++;
            }
          }
        });
      }
    };

    registry.register(plugin);
    await registry.install('store-test', sdk);

    const stores = sdk.getStores();
    expect(stores).toHaveProperty('pluginStore');
  });

  it('should isolate plugin stores', async () => {
    const plugin1: IPlugin = {
      name: 'plugin-1',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        sdk.createStore('store1', {
          state: () => ({ value: 'plugin1' })
        });
      }
    };

    const plugin2: IPlugin = {
      name: 'plugin-2',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        sdk.createStore('store2', {
          state: () => ({ value: 'plugin2' })
        });
      }
    };

    registry.register(plugin1);
    registry.register(plugin2);

    await registry.install('plugin-1', sdk);
    await registry.install('plugin-2', sdk);

    const stores = sdk.getStores();
    expect(stores.store1).not.toBe(stores.store2);
  });
});
```

---

## Implementation Tasks (After Tests)

### Day 2: Type Definitions

Create `src/plugins/types.ts`:
```typescript
export enum PluginStatus {
  REGISTERED = 'REGISTERED',
  INSTALLED = 'INSTALLED',
  ACTIVE = 'ACTIVE',
  INACTIVE = 'INACTIVE',
  ERROR = 'ERROR'
}

export interface IPlugin {
  name: string;
  version: string;
  description?: string;
  author?: string;
  homepage?: string;
  keywords?: string[];
  dependencies?: string[] | Record<string, string>;
  install?(sdk: IPlatformSDK): void | Promise<void>;
  activate?(): void | Promise<void>;
  deactivate?(): void | Promise<void>;
  uninstall?(): void | Promise<void>;
}

export interface IPluginMetadata extends IPlugin {
  status: PluginStatus;
  installedAt?: Date;
  activatedAt?: Date;
}

export interface IPluginRegistry {
  register(plugin: IPlugin): void;
  get(name: string): IPluginMetadata | undefined;
  getAll(): IPluginMetadata[];
  install(name: string, sdk: IPlatformSDK): Promise<void>;
  installAll(sdk: IPlatformSDK): Promise<void>;
  activate(name: string): Promise<void>;
  deactivate(name: string): Promise<void>;
  uninstall(name: string): Promise<void>;
}

export interface IPlatformSDK {
  api: any;
  events: any;
  addRoute(route: any): void;
  getRoutes(): any[];
  addComponent(name: string, component: any): void;
  getComponents(): Record<string, any>;
  createStore(id: string, options: any): string;
  getStores(): Record<string, any>;
}
```

### Day 3: PluginRegistry Implementation

### Day 4: PluginLoader & PlatformSDK

### Day 5: Documentation & Examples

---

## Acceptance Criteria

- [ ] All unit tests pass (30+ tests)
- [ ] All integration tests pass (10+ tests)
- [ ] Plugin registration works
- [ ] Lifecycle hooks execute correctly
- [ ] Dependency resolution works
- [ ] Circular dependencies detected
- [ ] PlatformSDK provides core APIs
- [ ] Code coverage ≥ 95%
- [ ] TypeScript strict mode (no `any`)
- [ ] Documentation complete

---

## Deliverables

1. ✅ Plugin interfaces and types
2. ✅ PluginRegistry class
3. ✅ PluginLoader with dependency resolution
4. ✅ PlatformSDK class
5. ✅ Plugin validation utilities
6. ✅ 30+ unit tests passing
7. ✅ 10+ integration tests passing
8. ✅ API documentation with examples

---

**Status**: ✅ Ready after Sprint 0
**Next Sprint**: Sprint 2 (API Client with mock HTTP server tests)
