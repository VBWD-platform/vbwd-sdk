# VBWD Core SDK - Sprint Implementation Plan

**Date**: 2025-12-26
**Status**: 📋 Planning Phase
**Approach**: TDD-First with Playwright TypeScript Tests
**Target**: Frontend Core SDK Implementation

---

## Executive Summary

The VBWD backend is complete with 144/144 tests passing (100%). The frontend requires a shared Core SDK that provides common functionality for both user and admin applications. This document outlines a TDD-first implementation plan using **unit and integration tests** for the SDK framework.

### Testing Strategy

**Core SDK (Framework Library)**:
- ✅ **Unit Tests** (Vitest): Test individual functions, classes, utilities
- ✅ **Integration Tests** (Vitest): Test how modules work together
- ✅ **Component Tests** (Vitest + Testing Library): Test Vue components in isolation
- ❌ **E2E Tests** (Playwright): NOT applicable - SDK is a library, not an app

**User & Admin Applications** (built ON TOP of SDK):
- ✅ **E2E Tests** (Playwright): Test complete user flows in the actual applications

### Implementation Strategy

1. **Write Unit Tests First**: Define expected behavior with Vitest tests
2. **Watch Tests Fail**: Ensure tests fail for the right reasons
3. **Implement Minimum Code**: Write just enough code to pass tests
4. **Refactor**: Clean up while keeping tests green
5. **Repeat**: Move to next feature

### Project Structure

```
vbwd-frontend/
├── core/                          # Core SDK (this sprint plan)
│   ├── src/
│   │   ├── plugins/              # Sprint 1
│   │   ├── api/                  # Sprint 2
│   │   ├── auth/                 # Sprint 3
│   │   ├── events/               # Sprint 4
│   │   ├── validation/           # Sprint 4
│   │   ├── components/           # Sprint 5
│   │   ├── composables/          # Sprint 6
│   │   └── access-control/       # Sprint 7
│   ├── tests/
│   │   ├── e2e/                  # Playwright tests
│   │   └── unit/                 # Vitest tests
│   └── package.json
├── user/vue/                      # User application
└── admin/vue/                     # Admin application
```

---

## Sprint Overview

| Sprint | Title | Duration | Focus | Tests |
|--------|-------|----------|-------|-------|
| 0 | Foundation | 1 week | Build setup, Playwright config | Infrastructure tests |
| 1 | Plugin System | 1 week | Plugin architecture | Plugin lifecycle tests |
| 2 | API Client | 2 weeks | HTTP layer, endpoints | API integration tests |
| 3 | Authentication | 1 week | Auth service, token mgmt | Auth flow tests |
| 4 | Event Bus & Validation | 1 week | Events, Zod schemas | Event & validation tests |
| 5 | UI Components | 2 weeks | Shared components | Component E2E tests |
| 6 | Composables | 1 week | Vue composables | Composable tests |
| 7 | Access Control | 1 week | Permissions, guards | Access control tests |
| 8 | Integration | 1 week | Final integration | Full E2E scenarios |

**Total Duration**: 10-11 weeks

---

## Test-First Development Principles

### 1. Unit Tests (Vitest)

**When to use**: Individual functions, classes, utilities

```typescript
// Example: test/unit/validation.spec.ts
describe('ValidationService', () => {
  it('validates email format', () => {
    const validator = new ValidationService();
    expect(validator.isEmail('test@example.com')).toBe(true);
    expect(validator.isEmail('invalid')).toBe(false);
  });
});
```

### 2. Integration Tests (Vitest)

**When to use**: Testing how multiple modules work together

```typescript
// Example: test/integration/plugin-api-integration.spec.ts
import { describe, it, expect } from 'vitest';
import { PluginRegistry } from '@/plugins/PluginRegistry';
import { ApiClient } from '@/api/ApiClient';
import { PlatformSDK } from '@/plugins/PlatformSDK';

describe('Plugin API Integration', () => {
  it('plugins can use API client from SDK', async () => {
    const api = new ApiClient({ baseURL: 'http://test' });
    const sdk = new PlatformSDK({ api });
    const registry = new PluginRegistry();

    let apiReceived = null;

    const plugin = {
      name: 'test',
      version: '1.0.0',
      install(sdk: IPlatformSDK) {
        apiReceived = sdk.api;
      }
    };

    registry.register(plugin);
    await registry.install('test', sdk);

    expect(apiReceived).toBe(api);
  });
});
```

### 3. Component Tests (Vitest + Testing Library)

**When to use**: Vue component behavior in isolation

```typescript
// Example: test/unit/Button.spec.ts
import { render, fireEvent } from '@testing-library/vue';
import Button from '@/components/Button.vue';

test('button emits click event', async () => {
  const { getByRole, emitted } = render(Button, {
    props: { label: 'Click me' }
  });

  await fireEvent.click(getByRole('button'));
  expect(emitted().click).toHaveLength(1);
});
```

### 4. E2E Tests (Playwright) - For Applications Only!

**Note**: E2E tests are NOT for the Core SDK. They are for the **user** and **admin** applications built on top of the SDK.

```typescript
// Example: user-app/tests/e2e/auth-flow.spec.ts (in user app, not SDK!)
test('user can login and access protected resources', async ({ page }) => {
  await page.goto('/login');
  await page.fill('[data-testid="email"]', 'user@example.com');
  await page.fill('[data-testid="password"]', 'password123');
  await page.click('[data-testid="login-button"]');
  await expect(page).toHaveURL('/cabinet');
});
```

---

## Sprint 0: Foundation & Testing Infrastructure

**Goal**: Establish build system and E2E testing foundation

### Test Scenarios (Write These First)

#### 1. Build & TypeScript Tests

```typescript
// tests/e2e/build.spec.ts
test('project builds without errors', async () => {
  const build = await exec('npm run build');
  expect(build.exitCode).toBe(0);
  expect(build.stderr).not.toContain('error');
});

test('TypeScript has no type errors', async () => {
  const typecheck = await exec('npm run type-check');
  expect(typecheck.exitCode).toBe(0);
});

test('strict mode is enabled', async () => {
  const tsconfig = await import('../tsconfig.json');
  expect(tsconfig.compilerOptions.strict).toBe(true);
  expect(tsconfig.compilerOptions.noImplicitAny).toBe(true);
});
```

#### 2. Test Infrastructure Tests

```typescript
// tests/e2e/test-infrastructure.spec.ts
test('Vitest can run unit tests', async () => {
  const test = await exec('npm run test:unit');
  expect(test.exitCode).toBe(0);
});

test('Playwright can run E2E tests', async () => {
  const test = await exec('npm run test:e2e');
  expect(test.exitCode).toBe(0);
});

test('Coverage reports are generated', async () => {
  await exec('npm run test:coverage');
  const coverageFile = await fs.access('coverage/index.html');
  expect(coverageFile).toBeDefined();
});
```

#### 3. Package Structure Tests

```typescript
// tests/e2e/package-structure.spec.ts
test('package.json has correct exports', async () => {
  const pkg = await import('../package.json');
  expect(pkg.type).toBe('module');
  expect(pkg.exports).toBeDefined();
  expect(pkg.exports['.'].import).toBeDefined();
  expect(pkg.exports['.'].require).toBeDefined();
});

test('dist folder contains ESM and CJS builds', async () => {
  await exec('npm run build');
  expect(await fs.access('dist/index.mjs')).toBeDefined();
  expect(await fs.access('dist/index.cjs')).toBeDefined();
  expect(await fs.access('dist/index.d.ts')).toBeDefined();
});
```

### Implementation Tasks (Do After Tests)

1. **Initialize Project**
   ```bash
   mkdir -p vbwd-frontend/core
   cd vbwd-frontend/core
   npm init -y
   ```

2. **Install Dependencies**
   ```bash
   # Core
   npm install vue@^3.4.0 vue-router@^4.0.0 pinia@^2.0.0 axios@^1.6.0 zod@^3.22.0

   # Dev Dependencies
   npm install -D typescript@^5.3.0 vite@^5.0.0 vitest@^1.0.0 \
     @playwright/test@^1.40.0 @vitejs/plugin-vue@^5.0.0 \
     @vue/test-utils@^2.4.0 @testing-library/vue@^8.0.0 \
     @types/node eslint@^8.0.0 prettier@^3.0.0
   ```

3. **Configure TypeScript** (`tsconfig.json`)
   ```json
   {
     "compilerOptions": {
       "target": "ES2022",
       "module": "ESNext",
       "lib": ["ES2022", "DOM", "DOM.Iterable"],
       "moduleResolution": "bundler",
       "strict": true,
       "noImplicitAny": true,
       "noImplicitThis": true,
       "strictNullChecks": true,
       "strictFunctionTypes": true,
       "strictPropertyInitialization": true,
       "noUnusedLocals": true,
       "noUnusedParameters": true,
       "noImplicitReturns": true,
       "noFallthroughCasesInSwitch": true,
       "esModuleInterop": true,
       "skipLibCheck": true,
       "jsx": "preserve",
       "declaration": true,
       "declarationMap": true,
       "sourceMap": true,
       "outDir": "./dist",
       "baseUrl": ".",
       "paths": {
         "@/*": ["./src/*"]
       }
     },
     "include": ["src/**/*"],
     "exclude": ["node_modules", "dist", "tests"]
   }
   ```

4. **Configure Vite** (`vite.config.ts`)
   ```typescript
   import { defineConfig } from 'vite';
   import vue from '@vitejs/plugin-vue';
   import { resolve } from 'path';

   export default defineConfig({
     plugins: [vue()],
     build: {
       lib: {
         entry: resolve(__dirname, 'src/index.ts'),
         name: 'VBWDCore',
         fileName: (format) => `index.${format === 'es' ? 'mjs' : 'cjs'}`,
         formats: ['es', 'cjs']
       },
       rollupOptions: {
         external: ['vue', 'vue-router', 'pinia', 'axios'],
         output: {
           globals: {
             vue: 'Vue',
             'vue-router': 'VueRouter',
             pinia: 'Pinia',
             axios: 'axios'
           }
         }
       }
     },
     resolve: {
       alias: {
         '@': resolve(__dirname, './src')
       }
     },
     test: {
       globals: true,
       environment: 'jsdom'
     }
   });
   ```

5. **Configure Playwright** (`playwright.config.ts`)
   ```typescript
   import { defineConfig, devices } from '@playwright/test';

   export default defineConfig({
     testDir: './tests/e2e',
     fullyParallel: true,
     forbidOnly: !!process.env.CI,
     retries: process.env.CI ? 2 : 0,
     workers: process.env.CI ? 1 : undefined,
     reporter: [
       ['html'],
       ['junit', { outputFile: 'test-results/e2e-results.xml' }],
       ['json', { outputFile: 'test-results/e2e-results.json' }]
     ],
     use: {
       baseURL: 'http://localhost:5173',
       trace: 'on-first-retry',
       screenshot: 'only-on-failure',
       video: 'retain-on-failure'
     },
     projects: [
       { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
       { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
       { name: 'webkit', use: { ...devices['Desktop Safari'] } }
     ],
     webServer: {
       command: 'npm run dev',
       url: 'http://localhost:5173',
       reuseExistingServer: !process.env.CI
     }
   });
   ```

6. **Create Directory Structure**
   ```bash
   mkdir -p src/{plugins,api,auth,events,validation,components,composables,access-control}
   mkdir -p tests/{e2e,unit}
   ```

7. **Create Entry Point** (`src/index.ts`)
   ```typescript
   // Placeholder - will be populated in later sprints
   export const version = '0.1.0';
   export const name = '@vbwd/core-sdk';
   ```

### Acceptance Criteria

- ✅ `npm run build` succeeds without errors
- ✅ `npm run test:unit` runs Vitest tests
- ✅ `npm run test:e2e` runs Playwright tests
- ✅ TypeScript strict mode enabled (no `any` types)
- ✅ ESLint and Prettier configured
- ✅ CI/CD pipeline runs all tests
- ✅ Test coverage reports generated
- ✅ Package builds ESM and CJS formats

### Deliverables

1. ✅ Working build system
2. ✅ Playwright E2E test suite
3. ✅ Vitest unit test suite
4. ✅ TypeScript configuration
5. ✅ ESLint + Prettier
6. ✅ CI/CD workflow
7. ✅ Documentation: README.md, CONTRIBUTING.md

---

## Sprint 1: Plugin System (TDD)

**Goal**: Implement extensible plugin architecture

### Test Scenarios (Write These First)

#### 1. Plugin Registration Tests

```typescript
// tests/e2e/plugin-registration.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Plugin Registration', () => {
  test('should register a plugin', async ({ page }) => {
    await page.goto('/test-harness');

    // Execute plugin registration
    await page.evaluate(() => {
      const registry = window.VBWD.PluginRegistry;
      const plugin = {
        name: 'test-plugin',
        version: '1.0.0',
        install(sdk) {
          sdk.addRoute({ path: '/test', component: 'TestComponent' });
        }
      };
      registry.register(plugin);
    });

    // Verify plugin is registered
    const plugins = await page.evaluate(() => {
      return window.VBWD.PluginRegistry.getAll();
    });

    expect(plugins).toHaveLength(1);
    expect(plugins[0].name).toBe('test-plugin');
  });

  test('should prevent duplicate plugin registration', async ({ page }) => {
    await page.goto('/test-harness');

    const error = await page.evaluate(() => {
      const registry = window.VBWD.PluginRegistry;
      const plugin = { name: 'duplicate', version: '1.0.0' };

      registry.register(plugin);

      try {
        registry.register(plugin);
        return null;
      } catch (e) {
        return e.message;
      }
    });

    expect(error).toContain('already registered');
  });
});
```

#### 2. Plugin Lifecycle Tests

```typescript
// tests/e2e/plugin-lifecycle.spec.ts
test('should execute plugin lifecycle hooks in order', async ({ page }) => {
  await page.goto('/test-harness');

  const callOrder = await page.evaluate(() => {
    const calls: string[] = [];

    const plugin = {
      name: 'lifecycle-test',
      version: '1.0.0',

      async install(sdk) {
        calls.push('install');
      },

      async activate() {
        calls.push('activate');
      },

      async deactivate() {
        calls.push('deactivate');
      },

      async uninstall() {
        calls.push('uninstall');
      }
    };

    const registry = window.VBWD.PluginRegistry;
    await registry.register(plugin);
    await registry.activate('lifecycle-test');
    await registry.deactivate('lifecycle-test');
    await registry.uninstall('lifecycle-test');

    return calls;
  });

  expect(callOrder).toEqual([
    'install',
    'activate',
    'deactivate',
    'uninstall'
  ]);
});
```

#### 3. Plugin Dependency Tests

```typescript
// tests/e2e/plugin-dependencies.spec.ts
test('should load plugins in dependency order', async ({ page }) => {
  await page.goto('/test-harness');

  const loadOrder = await page.evaluate(() => {
    const loaded: string[] = [];

    const pluginA = {
      name: 'plugin-a',
      version: '1.0.0',
      dependencies: ['plugin-b'],
      install() { loaded.push('a'); }
    };

    const pluginB = {
      name: 'plugin-b',
      version: '1.0.0',
      install() { loaded.push('b'); }
    };

    const registry = window.VBWD.PluginRegistry;
    registry.register(pluginA);
    registry.register(pluginB);
    registry.loadAll();

    return loaded;
  });

  // Plugin B should load before A (dependency)
  expect(loadOrder).toEqual(['b', 'a']);
});

test('should detect circular dependencies', async ({ page }) => {
  await page.goto('/test-harness');

  const error = await page.evaluate(() => {
    const pluginA = {
      name: 'plugin-a',
      dependencies: ['plugin-b']
    };

    const pluginB = {
      name: 'plugin-b',
      dependencies: ['plugin-a']
    };

    const registry = window.VBWD.PluginRegistry;
    registry.register(pluginA);
    registry.register(pluginB);

    try {
      registry.loadAll();
      return null;
    } catch (e) {
      return e.message;
    }
  });

  expect(error).toContain('circular dependency');
});
```

### Implementation Tasks (Do After Tests Pass)

1. **Create Plugin Interface** (`src/plugins/types.ts`)
2. **Implement PluginRegistry** (`src/plugins/PluginRegistry.ts`)
3. **Implement PluginLoader** (`src/plugins/PluginLoader.ts`)
4. **Create PlatformSDK** (`src/plugins/PlatformSDK.ts`)
5. **Add Plugin Status Tracking**
6. **Implement Dependency Resolution**

### Acceptance Criteria

- ✅ All Playwright E2E tests pass
- ✅ Plugin registration works
- ✅ Lifecycle hooks execute in order
- ✅ Dependency resolution works
- ✅ Circular dependencies detected
- ✅ 95%+ code coverage

---

## Sprint 2: API Client (TDD)

**Goal**: Type-safe HTTP client with backend integration

### Test Scenarios (Write These First)

#### 1. Authentication API Tests

```typescript
// tests/e2e/api-auth.spec.ts
test('should login user and receive JWT token', async ({ request }) => {
  const response = await request.post('http://localhost:5001/api/v1/auth/login', {
    data: {
      email: 'test@example.com',
      password: 'password123'
    }
  });

  expect(response.ok()).toBeTruthy();
  const data = await response.json();

  expect(data).toHaveProperty('token');
  expect(data).toHaveProperty('user');
  expect(data.user.email).toBe('test@example.com');
  expect(typeof data.token).toBe('string');
  expect(data.token.length).toBeGreaterThan(0);
});

test('should reject invalid credentials', async ({ request }) => {
  const response = await request.post('http://localhost:5001/api/v1/auth/login', {
    data: {
      email: 'test@example.com',
      password: 'wrongpassword'
    }
  });

  expect(response.status()).toBe(401);
  const data = await response.json();
  expect(data.error).toContain('Invalid credentials');
});

test('should register new user', async ({ request }) => {
  const email = `test${Date.now()}@example.com`;

  const response = await request.post('http://localhost:5001/api/v1/auth/register', {
    data: {
      email,
      password: 'password123',
      name: 'Test User'
    }
  });

  expect(response.ok()).toBeTruthy();
  const data = await response.json();

  expect(data).toHaveProperty('user');
  expect(data.user.email).toBe(email);
});
```

#### 2. Protected Endpoint Tests

```typescript
// tests/e2e/api-protected.spec.ts
test('should access protected endpoint with token', async ({ request }) => {
  // 1. Login to get token
  const loginResponse = await request.post('http://localhost:5001/api/v1/auth/login', {
    data: { email: 'test@example.com', password: 'password123' }
  });
  const { token } = await loginResponse.json();

  // 2. Access protected endpoint
  const profileResponse = await request.get('http://localhost:5001/api/v1/user/profile', {
    headers: { Authorization: `Bearer ${token}` }
  });

  expect(profileResponse.ok()).toBeTruthy();
  const profile = await profileResponse.json();
  expect(profile).toHaveProperty('email');
});

test('should reject request without token', async ({ request }) => {
  const response = await request.get('http://localhost:5001/api/v1/user/profile');

  expect(response.status()).toBe(401);
  const data = await response.json();
  expect(data.error).toContain('Authorization header required');
});

test('should reject request with invalid token', async ({ request }) => {
  const response = await request.get('http://localhost:5001/api/v1/user/profile', {
    headers: { Authorization: 'Bearer invalid-token' }
  });

  expect(response.status()).toBe(401);
});
```

#### 3. API Client Interceptor Tests

```typescript
// tests/unit/api-interceptors.spec.ts
import { ApiClient } from '@/api/ApiClient';

test('should automatically add auth token to requests', async () => {
  const client = new ApiClient({ baseURL: 'http://localhost:5001' });
  client.setToken('test-token');

  const requestConfig = client.interceptors.request[0]({
    url: '/api/v1/user/profile',
    method: 'GET'
  });

  expect(requestConfig.headers.Authorization).toBe('Bearer test-token');
});

test('should refresh token on 401 response', async () => {
  const client = new ApiClient({ baseURL: 'http://localhost:5001' });
  const refreshSpy = vi.fn(() => Promise.resolve('new-token'));

  client.on('token-expired', refreshSpy);

  // Simulate 401 response
  await client.interceptors.response[0]({
    status: 401,
    data: { error: 'Token expired' }
  });

  expect(refreshSpy).toHaveBeenCalled();
});
```

### Implementation Tasks (Do After Tests Pass)

1. **Create API Types** (`src/api/types.ts`)
2. **Implement ApiClient** (`src/api/ApiClient.ts`)
3. **Create Endpoint Definitions** (`src/api/endpoints/`)
4. **Implement Interceptors** (`src/api/interceptors.ts`)
5. **Add Error Handling** (`src/api/errors.ts`)
6. **Create API Composable** (`src/composables/useApi.ts`)

### Acceptance Criteria

- ✅ All API endpoints typed
- ✅ Token management works
- ✅ Interceptors function correctly
- ✅ Error normalization works
- ✅ E2E tests pass against real backend
- ✅ 95%+ code coverage

---

## Sprint 3-8: Remaining Sprints

*(Similar detailed TDD plans for Authentication, Event Bus, UI Components, Composables, Access Control, and Integration sprints)*

---

## Development Workflow

### Daily TDD Cycle

1. **Morning**: Write E2E tests for today's feature
2. **Mid-Day**: Watch tests fail (red)
3. **Afternoon**: Implement minimum code to pass (green)
4. **Evening**: Refactor and optimize (refactor)
5. **EOD**: Commit with passing tests

### Pull Request Requirements

- ✅ All E2E tests pass
- ✅ All unit tests pass
- ✅ Code coverage ≥ 95%
- ✅ TypeScript builds without errors
- ✅ ESLint passes (no warnings)
- ✅ Playwright visual regression tests pass

### CI/CD Pipeline

```yaml
# .github/workflows/core-sdk-ci.yml
name: Core SDK CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: TypeScript check
        run: npm run type-check

      - name: Lint
        run: npm run lint

      - name: Unit tests
        run: npm run test:unit -- --coverage

      - name: E2E tests
        run: npm run test:e2e

      - name: Build
        run: npm run build

      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

---

## Success Metrics

### Code Quality
- **Test Coverage**: ≥ 95%
- **TypeScript Strict**: 100% (no `any` types)
- **ESLint Errors**: 0
- **Build Warnings**: 0

### Performance
- **Build Time**: < 30 seconds
- **Test Suite**: < 2 minutes
- **Bundle Size**: < 100KB (gzipped)

### Documentation
- **API Documentation**: 100% coverage (TypeDoc)
- **Usage Examples**: All public APIs
- **Migration Guides**: Complete

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Backend API changes | High | Version API, maintain backwards compatibility |
| Browser compatibility | Medium | Test on Chrome, Firefox, Safari |
| Type safety gaps | High | Strict TypeScript, no `any` |
| Test maintenance | Medium | Playwright auto-wait, stable selectors |
| Bundle size bloat | Low | Tree-shaking, code splitting |

---

## Next Steps

1. **Immediate**: Create Core SDK project structure (Sprint 0)
2. **Week 1**: Complete foundation and testing setup
3. **Week 2**: Implement plugin system (Sprint 1)
4. **Week 3-4**: Build API client (Sprint 2)
5. **Week 5**: Authentication service (Sprint 3)

---

**Document Status**: ✅ Ready for Implementation
**Approved By**: Architecture Team
**Start Date**: TBD
**Estimated Completion**: 10-11 weeks
