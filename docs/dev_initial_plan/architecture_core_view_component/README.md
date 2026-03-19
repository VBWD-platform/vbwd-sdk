# VBWD Core View Component Architecture

**Project:** VBWD-SDK - Shared Core Module for User & Admin Applications
**Status:** Active Development
**Last Updated:** 2026-01-05
**License:** BSL 1.1 (Business Source Licence)

---

## Implementation Status (2026-01-05)

| Feature | Status | Notes |
|---------|--------|-------|
| **Package Structure** | ✅ Implemented | `@vbwd/view-component` in `frontend/core/` |
| **Plugin System** | ✅ Implemented | PluginRegistry, IPlatformSDK, lifecycle |
| **API Client** | ✅ Implemented | ApiClient class in core |
| **Event Bus** | ✅ Implemented | EventBus with typed events |
| **Auth Store** | ✅ Implemented | Shared auth store |
| **Subscription Store** | ✅ Implemented | Feature access control |
| **Route Guards** | ✅ Implemented | AuthGuard, RoleGuard |
| **Composables** | ✅ Implemented | useFeatureAccess |
| **API Types** | ✅ Implemented | Shared types for API responses |
| **UI Components** | ⚠️ Partial | Forms, layout, access components |

### Architecture Decision (2026-01-05)

**Decision:** Hybrid architecture - Plugin system is for extensibility, not for core features.

**What the plugin system is FOR:**
- Payment provider integrations (Stripe, PayPal, custom providers)
- Value-added service integrations (CRM, email marketing, analytics)
- Third-party integrations and custom extensions

**What the plugin system is NOT FOR:**
- Core business features (users, plans, subscriptions, invoices)
- These use flat `src/views/` and `src/stores/` structure

### Plugin System (View-Core)

Located in `frontend/core/src/plugins/`:

| File | Purpose |
|------|---------|
| `types.ts` | `IPlugin`, `IPlatformSDK`, `IPluginRegistry` interfaces |
| `PluginRegistry.ts` | Plugin registration, lifecycle, dependency resolution |
| `PlatformSDK.ts` | SDK instance for plugins (routes, components, stores) |
| `utils/semver.ts` | Semantic versioning utilities |

**Plugin Interface:**
```typescript
interface IPlugin {
  name: string;
  version: string;
  dependencies?: string[] | Record<string, string>;
  install?(sdk: IPlatformSDK): void | Promise<void>;
  activate?(): void | Promise<void>;
  deactivate?(): void | Promise<void>;
  uninstall?(): void | Promise<void>;
}
```

**Plugin Lifecycle:**
```
REGISTERED → INSTALLED → ACTIVE ⇄ INACTIVE
```

**Usage (for payment/integration plugins):**
```typescript
import { PluginRegistry, PlatformSDK } from '@vbwd/view-component';

const registry = new PluginRegistry();
const sdk = new PlatformSDK(app, router);

// Register payment provider plugins
registry.register(stripePlugin);
registry.register(paypalPlugin);
await registry.installAll(sdk);
await registry.activate('stripe-payment');
```

### Core SDK Usage (Decisions 2026-01-05)

The core SDK provides shared infrastructure that apps **must** use:

| Component | Current State | Decision | Migration |
|-----------|---------------|----------|-----------|
| **Plugin System** | ✅ For plugins | Keep for payment/integrations | N/A |
| **API Client** | ❌ Local api.ts | **Use core's ApiClient** | Planned |
| **Auth Store** | ❌ Local auth.ts | **Use core's auth store** | Planned |
| **Event Bus** | ❌ Not used | **Integrate** (FE→BE events) | Planned |
| **Route Guards** | ✅ Uses guards | Keep as-is | N/A |
| **Stores** | Flat stores/ | **Keep flat structure** | N/A |

### EventBus Purpose

The EventBus is used for **frontend-to-backend event communication**:
- Frontend emits events (user actions, state changes)
- Backend receives and processes events (analytics, webhooks, logging)
- Enables decoupled event-driven architecture

```typescript
// Example: Frontend emits event
eventBus.emit('subscription:cancelled', {
  subscriptionId: '123',
  reason: 'user_request'
});

// Backend webhook receives and processes
```

### CLI Plugin Manager (Planned)

Applications extending view-core (admin, user) should include a CLI for plugin management.

**Core SDK provides:** `PluginManagerCLI` class that wraps `PluginRegistry`

**Commands:**

```bash
plugin list                  # List plugins with status
plugin install <name>        # Install from registry or path
plugin uninstall <name>      # Remove plugin
plugin activate <name>       # Enable plugin
plugin deactivate <name>     # Disable plugin
plugin help                  # Show help
```

**Integration in apps:**

```typescript
// bin/plugin-manager.ts
import { PluginManagerCLI } from '@vbwd/view-component';
import { registry } from '../src/plugins';

const cli = new PluginManagerCLI(registry, {
  pluginsDir: './src/plugins',
  configFile: './plugins.json'
});

cli.run(process.argv.slice(2));
```

**Configuration (`plugins.json`):**

```json
{
  "plugins": {
    "stripe-payment": { "enabled": true, "version": "1.2.0" },
    "paypal-payment": { "enabled": false, "version": "1.1.0" }
  }
}
```

---

## 1. Overview

The **VBWD Core View Compoentent** (`vbwd-component`) is a shared TypeScript module that provides common functionality for both the user-facing application and the admin application. This ensures consistency, reduces code duplication, and maintains a single source of truth for core features.

### Key Principle: DRY (Don't Repeat Yourself)

Both apps share the same:
- Plugin system architecture
- API client and authenticationf
- Type definitions
- Validation schemas
- Event bus
- UI component library (base components)

---

## 2. Directory Structure

```
frontend/
├── core/                          # Core View Compoentent (shared module)
│   ├── package.json               # Core View Compoententpackage definition
│   ├── tsconfig.json              # TypeScript config
│   ├── src/
│   │   ├── index.ts               # Main exports
│   │   │
│   │   ├── plugin/                # Plugin system
│   │   │   ├── IPlugin.ts
│   │   │   ├── PluginRegistry.ts
│   │   │   ├── PluginLoader.ts
│   │   │   └── types.ts
│   │   │
│   │   ├── api/                   # API Client
│   │   │   ├── IApiClient.ts
│   │   │   ├── ApiClient.ts
│   │   │   ├── interceptors.ts
│   │   │   └── types/
│   │   │       ├── auth.types.ts
│   │   │       ├── user.types.ts
│   │   │       ├── admin.types.ts
│   │   │       └── common.types.ts
│   │   │
│   │   ├── auth/                  # Authentication
│   │   │   ├── IAuthService.ts
│   │   │   ├── AuthService.ts
│   │   │   └── authStore.ts
│   │   │
│   │   ├── events/                # Event Bus
│   │   │   ├── IEventBus.ts
│   │   │   ├── EventBus.ts
│   │   │   └── events.ts
│   │   │
│   │   ├── validation/            # Validation
│   │   │   ├── IValidationService.ts
│   │   │   ├── ValidationService.ts
│   │   │   └── schemas/
│   │   │
│   │   ├── access/                # Access Control
│   │   │   ├── AccessControl.ts
│   │   │   └── permissions.ts
│   │   │
│   │   ├── sdk/                   # Platform SDK
│   │   │   └── PlatformSDK.ts
│   │   │
│   │   ├── components/            # Shared UI Components
│   │   │   ├── Button.vue
│   │   │   ├── Input.vue
│   │   │   ├── Modal.vue
│   │   │   ├── Table.vue
│   │   │   └── ...
│   │   │
│   │   ├── composables/           # Shared Composables
│   │   │   ├── useApi.ts
│   │   │   ├── useAuth.ts
│   │   │   ├── useForm.ts
│   │   │   └── useNotification.ts
│   │   │
│   │   └── utils/                 # Utilities
│   │       ├── format.ts
│   │       ├── date.ts
│   │       └── storage.ts
│   │
│   └── __tests__/                 # Core View Compoentent tests
│       ├── unit/
│       └── integration/
│
├── user/vue/                      # User-facing app
│   ├── package.json
│   ├── src/
│   │   ├── plugins/               # User-specific plugins
│   │   │   ├── wizard/
│   │   │   └── user-cabinet/
│   │   ├── main.ts
│   │   └── App.vue
│   └── node_modules/
│       └── @vbwd/core -> ../../core  # Symlink
│
└── admin/vue/                     # Admin app
    ├── package.json
    ├── src/
    │   ├── plugins/               # Admin-specific plugins
    │   │   ├── user-management/
    │   │   ├── plan-management/
    │   │   ├── analytics/
    │   │   └── invoice-management/
    │   ├── main.ts
    │   └── App.vue
    └── node_modules/
        └── @vbwd/core -> ../../core  # Symlink
```

---

## 3. Core View Compoentent Modules

### 3.1 Plugin System

**Exports:**
```typescript
export { IPlugin, PluginRoute, PluginComponent, PluginStore } from './plugin/IPlugin';
export { PluginRegistry } from './plugin/PluginRegistry';
export { PluginLoader } from './plugin/PluginLoader';
```

**Purpose:** Provides plugin architecture for both user and admin apps.

---

### 3.2 API Client

**Exports:**
```typescript
export { IApiClient } from './api/IApiClient';
export { ApiClient } from './api/ApiClient';
export * from './api/types';
```

**Purpose:** Type-safe HTTP client with Axios, interceptors, and token management.

**Endpoints:**
- `auth`: Authentication endpoints (shared)
- `user`: User-facing endpoints
- `admin`: Admin-only endpoints
- `tariffs`: Tariff plan management
- `checkout`: Checkout and payments

---

### 3.3 Authentication Service

**Exports:**
```typescript
export { IAuthService } from './auth/IAuthService';
export { AuthService } from './auth/AuthService';
export { useAuthStore } from './auth/authStore';
```

**Purpose:** JWT authentication, session management, and role-based access control.

**Features:**
- Login/Register/Logout
- Token refresh
- Permission checking
- Role verification (user, admin)

---

### 3.4 Event Bus

**Exports:**
```typescript
export { IEventBus } from './events/IEventBus';
export { EventBus } from './events/EventBus';
export { PlatformEvents } from './events/events';
```

**Purpose:** Decoupled communication between plugins and core.

---

### 3.5 Validation Service

**Exports:**
```typescript
export { IValidationService } from './validation/IValidationService';
export { ValidationService } from './validation/ValidationService';
export * from './validation/schemas';
```

**Purpose:** Zod-based validation with reusable schemas.

---

### 3.6 Access Control

**Exports:**
```typescript
export { AccessControl } from './access/AccessControl';
export { useAccessControl } from './access/composables';
export { Permissions, Roles } from './access/permissions';
```

**Purpose:** Tariff-based and role-based access control.

---

### 3.7 Shared UI Components

**Exports:**
```typescript
export { Button, Input, Modal, Table } from './components';
```

**Purpose:** Reusable, accessible UI components styled with Tailwind CSS.

---

### 3.8 Composables

**Exports:**
```typescript
export { useApi } from './composables/useApi';
export { useAuth } from './composables/useAuth';
export { useForm } from './composables/useForm';
export { useNotification } from './composables/useNotification';
```

**Purpose:** Reusable Vue 3 composition functions.

---

### 3.9 Platform SDK

**Exports:**
```typescript
export { PlatformSDK, createPlatformSDK } from './sdk/PlatformSDK';
```

**Purpose:** Unified SDK interface for plugins.

---

## 4. Installation & Symlink Setup

### 4.1 Development Setup (Symlinks)

During development, use symlinks to share the core SDK:

```bash
# From frontend/user/vue/
npm link ../../core

# From frontend/admin/vue/
npm link ../../core
```

**package.json** (both user and admin apps):
```json
{
  "dependencies": {
    "@vbwd/core": "file:../../core"
  }
}
```

### 4.2 Future: Separate NPM Package

Later, publish as `@vbwd/view-component`:

```bash
cd frontend/core
npm publish
```

Then in user and admin apps:
```json
{
  "dependencies": {
    "@vbwd/view-component": "^1.0.0"
  }
}
```

---

## 5. Usage in Applications

### 5.1 User App (frontend/user/vue/)

**main.ts:**
```typescript
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { createRouter, createWebHistory } from 'vue-router';
import App from './App.vue';

// Import from core SDK
import {
  createPlatformSDK,
  PluginRegistry,
  ApiClient,
  AuthService,
  EventBus
} from '@vbwd/core';

// User-specific plugins
import { WizardPlugin } from './plugins/wizard';
import { UserCabinetPlugin } from './plugins/user-cabinet';

async function bootstrap() {
  const app = createApp(App);
  const pinia = createPinia();
  const router = createRouter({
    history: createWebHistory(),
    routes: [],
  });

  app.use(pinia);
  app.use(router);

  // Create SDK
  const sdk = createPlatformSDK(app, router);

  // Register user plugins
  const registry = new PluginRegistry();
  registry.register(new WizardPlugin());
  registry.register(new UserCabinetPlugin());
  await registry.loadAll(app, sdk);

  app.mount('#app');
}

bootstrap();
```

---

### 5.2 Admin App (frontend/admin/vue/)

**main.ts:**
```typescript
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { createRouter, createWebHistory } from 'vue-router';
import App from './App.vue';

// Import from core SDK (same imports!)
import {
  createPlatformSDK,
  PluginRegistry,
  ApiClient,
  AuthService,
  EventBus
} from '@vbwd/core';

// Admin-specific plugins
import { UserManagementPlugin } from './plugins/user-management';
import { PlanManagementPlugin } from './plugins/plan-management';
import { AnalyticsPlugin } from './plugins/analytics';
import { InvoiceManagementPlugin } from './plugins/invoice-management';

async function bootstrap() {
  const app = createApp(App);
  const pinia = createPinia();
  const router = createRouter({
    history: createWebHistory('/admin'),  // Different base path
    routes: [],
  });

  app.use(pinia);
  app.use(router);

  // Create SDK (same API!)
  const sdk = createPlatformSDK(app, router);

  // Register admin plugins
  const registry = new PluginRegistry();
  registry.register(new UserManagementPlugin());
  registry.register(new PlanManagementPlugin());
  registry.register(new AnalyticsPlugin());
  registry.register(new InvoiceManagementPlugin());
  await registry.loadAll(app, sdk);

  app.mount('#app');
}

bootstrap();
```

---

## 6. Testing Core SDK

### 6.1 Unit Tests

```bash
cd frontend/core
npm run test:unit
```

**Coverage Target:** 95%+ for core SDK

### 6.2 Integration Tests

Core SDK is tested through both user and admin app E2E tests.

---

## 7. Development Workflow

### 7.1 Making Changes to Core SDK

1. Edit files in `frontend/core/src/`
2. Both user and admin apps automatically see changes (via symlink)
3. Test changes in both apps
4. Commit core SDK changes separately

### 7.2 Version Management

**Current (Development):**
- Core SDK version: `0.1.0-dev`
- No versioning needed with symlinks

**Future (Published Package):**
- Core SDK: Semantic versioning (`1.0.0`, `1.1.0`, etc.)
- User app: Specify core version in package.json
- Admin app: Specify core version in package.json

---

## 8. Core SDK Package Definition

**frontend/core/package.json:**
```json
{
  "name": "@vbwd/core-sdk",
  "version": "0.1.0",
  "description": "Shared core SDK for VBWD user and admin applications",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "test:unit": "vitest",
    "lint": "eslint src --ext .ts",
    "format": "prettier --write src"
  },
  "keywords": ["vbwd", "sdk", "vue", "typescript"],
  "license": "BSL-1.1",
  "peerDependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.2.0",
    "pinia": "^2.1.0",
    "axios": "^1.6.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "vitest": "^1.1.0",
    "@vue/test-utils": "^2.4.0",
    "eslint": "^8.56.0",
    "prettier": "^3.1.0"
  }
}
```

---

## 9. Benefits of Shared Core SDK

### 9.1 Consistency
- Same API client for both apps
- Same authentication logic
- Same validation schemas
- Same UI components

### 9.2 Maintainability
- Single source of truth
- Fix bugs once, applies to both apps
- Easier to add features

### 9.3 Type Safety
- Shared types ensure consistency
- TypeScript catches integration issues early

### 9.4 Testability
- Test core SDK once
- Reduces test duplication
- Higher confidence in both apps

### 9.5 Developer Experience
- Learn once, use everywhere
- Consistent patterns
- Easy to switch between user and admin development

---

## 10. Migration Path

### Phase 1: Current (Symlinks)
```
frontend/core/           # Development
frontend/user/vue/node_modules/@vbwd/core -> symlink
frontend/admin/vue/node_modules/@vbwd/core -> symlink
```

### Phase 2: Private NPM Registry
```
npm publish @vbwd/core-sdk to private registry
npm install @vbwd/core-sdk in both apps
```

### Phase 3: Public NPM Package (Optional)
```
npm publish @vbwd/core-sdk to npmjs.com
npm install @vbwd/core-sdk (public)
```

---

## 11. Core SDK Exports

**frontend/core/src/index.ts:**
```typescript
// Plugin System
export * from './plugin';

// API Client
export * from './api';

// Authentication
export * from './auth';

// Events
export * from './events';

// Validation
export * from './validation';

// Access Control
export * from './access';

// Platform SDK
export * from './sdk';

// Components
export * from './components';

// Composables
export * from './composables';

// Utils
export * from './utils';

// Types
export * from './types';
```

---

## Related Documentation

- [User App Architecture](../architecture_core_view_user/README.md)
- [Admin App Architecture](../architecture_core_view_admin/README.md)
- [Server Architecture](../architecture_server/README.md)
