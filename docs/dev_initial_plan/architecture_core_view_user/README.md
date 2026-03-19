# VBWD-SDK Frontend Architecture

**Project:** VBWD-SDK - Digital Subscriptions & SaaS Sales Platform (Frontend)
**Status:** Initial Development
**License:** BSL 1.1 (Business Source Licence)

---

## 1. Project Overview

VBWD-SDK Frontend is a **plugin-based Vue.js 3 + TypeScript** platform for digital subscriptions and SaaS sales. The architecture emphasizes:

- **Plugin SDK**: Extensible plugin system for adding features
- **API Client SDK**: Unified, type-safe communication with backend
- **Component Library**: Reusable UI components following design system
- **State Management**: Pinia stores with plugin isolation
- **Type Safety**: Full TypeScript coverage with strict mode
- **Testing**: Playwright E2E tests + Vitest unit tests

### Core Philosophy

The frontend is **not just an application** - it's a **platform** and **SDK** for building subscription-based SaaS interfaces. Plugins can:

- Register routes and pages
- Add components to extension points
- Access shared services (API client, auth, state)
- Define their own state stores
- Contribute to navigation and UI

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VBWD Frontend Platform                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Application Shell                       │   │
│  │  - Router (Vue Router)                                   │   │
│  │  - Plugin Loader & Registry                              │   │
│  │  - Global State (Pinia)                                  │   │
│  │  - Layout System                                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Core SDK Layer                         │   │
│  │  - API Client (Axios + Type-safe wrappers)              │   │
│  │  - Auth Service (JWT, session management)               │   │
│  │  - Plugin API (IPlugin interface)                       │   │
│  │  - Event Bus (plugin communication)                     │   │
│  │  - Validation Service (Zod schemas)                     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Plugin Layer                          │   │
│  │                                                          │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐     │   │
│  │  │  Wizard    │  │ User       │  │ Admin          │     │   │
│  │  │  Plugin    │  │ Cabinet    │  │ Dashboard      │     │   │
│  │  │            │  │ Plugin     │  │ Plugin         │     │   │
│  │  └────────────┘  └────────────┘  └────────────────┘     │   │
│  │                                                          │   │
│  │  Each plugin:                                            │   │
│  │  - Implements IPlugin interface                         │   │
│  │  - Registers routes, components, stores                 │   │
│  │  - Isolated state management                            │   │
│  │  - Can access SDK services                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────┐
                  │  Backend API   │
                  │  (Flask)       │
                  └────────────────┘
```

### 2.2 Technology Stack

| Layer              | Technology              | Purpose                          |
|--------------------|-------------------------|----------------------------------|
| Framework          | Vue.js 3 (Composition API) | Reactive UI framework         |
| Language           | TypeScript 5.x          | Type safety and developer experience |
| Build Tool         | Vite 5.x                | Fast development and optimized builds |
| Routing            | Vue Router 4            | Client-side routing with plugins |
| State Management   | Pinia 2.x               | Type-safe, modular state stores |
| HTTP Client        | Axios                   | API communication with interceptors |
| Validation         | Zod                     | Schema validation and type inference |
| UI Components      | Custom + Headless UI    | Accessible, composable components |
| Styling            | Tailwind CSS 3.x        | Utility-first styling system |
| E2E Testing        | Playwright              | Full browser automation testing |
| Unit Testing       | Vitest                  | Fast Vite-native unit tests |
| Linting            | ESLint + Prettier       | Code quality and formatting |

---

## 3. Plugin System Architecture

### 3.1 Plugin Interface (ISP Compliance)

Every plugin implements the `IPlugin` interface:

```typescript
// src/core/plugin/IPlugin.ts
export interface IPlugin {
  // Plugin metadata
  readonly name: string;
  readonly version: string;
  readonly dependencies?: string[];

  // Lifecycle hooks
  install(app: App, sdk: PlatformSDK): Promise<void>;
  activate?(): Promise<void>;
  deactivate?(): Promise<void>;

  // Optional capabilities
  registerRoutes?(): PluginRoute[];
  registerComponents?(): PluginComponent[];
  registerStores?(): PluginStore[];
  registerMiddleware?(): PluginMiddleware[];
}

export interface PluginRoute {
  path: string;
  component: Component;
  meta?: RouteMeta & {
    requiresAuth?: boolean;
    requiredPlan?: string[];
    permissions?: string[];
  };
}

export interface PluginComponent {
  name: string;
  component: Component;
  slot?: string; // Extension point name
}

export interface PluginStore {
  id: string;
  store: StoreDefinition;
}
```

### 3.2 Plugin Loader & Registry

```typescript
// src/core/plugin/PluginRegistry.ts
export class PluginRegistry {
  private plugins: Map<string, IPlugin> = new Map();
  private loadedPlugins: Set<string> = new Set();

  register(plugin: IPlugin): void {
    // Validate dependencies
    // Check for conflicts
    // Register plugin
  }

  async loadPlugin(name: string, sdk: PlatformSDK): Promise<void> {
    // Load plugin
    // Install plugin
    // Activate plugin
  }

  getPlugin(name: string): IPlugin | undefined {
    return this.plugins.get(name);
  }
}
```

### 3.3 Platform SDK

The SDK provides services to plugins:

```typescript
// src/core/sdk/PlatformSDK.ts
export interface PlatformSDK {
  // Core services (injected via DI)
  apiClient: IApiClient;
  authService: IAuthService;
  validationService: IValidationService;
  eventBus: IEventBus;

  // Router access
  router: Router;

  // Store access
  useStore: <T>(storeId: string) => T;

  // Component registration
  registerGlobalComponent(name: string, component: Component): void;

  // Extension points
  registerExtensionPoint(name: string, slot: ExtensionPoint): void;
  contributeToExtensionPoint(name: string, component: Component): void;
}
```

---

## 4. Core SDK Layer

### 4.1 API Client (Type-Safe)

```typescript
// src/core/api/ApiClient.ts
export interface IApiClient {
  // Auth
  auth: {
    login(email: string, password: string): Promise<AuthResponse>;
    register(data: RegisterRequest): Promise<AuthResponse>;
    logout(): Promise<void>;
    refreshToken(): Promise<TokenRefreshResponse>;
  };

  // User
  user: {
    getProfile(): Promise<UserProfile>;
    updateProfile(data: Partial<UserProfile>): Promise<UserProfile>;
    getSubscriptions(): Promise<Subscription[]>;
    getInvoices(): Promise<Invoice[]>;
  };

  // Tariff Plans
  tariffs: {
    list(): Promise<TariffPlan[]>;
    get(slug: string): Promise<TariffPlan>;
  };

  // Checkout
  checkout: {
    create(data: CheckoutRequest): Promise<CheckoutSession>;
    confirm(sessionId: string): Promise<CheckoutConfirmation>;
  };

  // Generic methods
  get<T>(url: string, config?: AxiosRequestConfig): Promise<T>;
  post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T>;
  put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T>;
  delete<T>(url: string, config?: AxiosRequestConfig): Promise<T>;
}
```

**Implementation:**
- Axios-based with interceptors for auth tokens
- Automatic token refresh on 401
- Request/response type inference
- Error normalization
- Loading state management

### 4.2 Auth Service

```typescript
// src/core/auth/IAuthService.ts
export interface IAuthService {
  // State
  isAuthenticated: ComputedRef<boolean>;
  currentUser: ComputedRef<User | null>;

  // Methods
  login(email: string, password: string): Promise<void>;
  register(data: RegisterData): Promise<void>;
  logout(): Promise<void>;
  refreshSession(): Promise<void>;

  // Token management
  getAccessToken(): string | null;
  setAccessToken(token: string): void;
  clearTokens(): void;

  // Permissions
  hasPermission(permission: string): boolean;
  hasRole(role: string): boolean;
  canAccessPlan(planSlug: string): boolean;
}
```

### 4.3 Validation Service

```typescript
// src/core/validation/IValidationService.ts
export interface IValidationService {
  // Schema validation (Zod)
  validate<T>(schema: z.ZodSchema<T>, data: unknown): ValidationResult<T>;

  // Predefined schemas
  schemas: {
    email: z.ZodString;
    password: z.ZodString;
    fileUpload: z.ZodObject<any>;
    gdprConsent: z.ZodBoolean;
  };

  // Custom validators
  registerValidator(name: string, validator: ValidatorFn): void;
}
```

### 4.4 Event Bus

```typescript
// src/core/events/IEventBus.ts
export interface IEventBus {
  // Publish events
  emit<T = any>(event: string, payload?: T): void;

  // Subscribe to events
  on<T = any>(event: string, handler: (payload: T) => void): () => void;

  // Once
  once<T = any>(event: string, handler: (payload: T) => void): void;

  // Unsubscribe
  off(event: string, handler?: Function): void;
}

// Predefined events
export enum PlatformEvents {
  USER_LOGGED_IN = 'user:logged-in',
  USER_LOGGED_OUT = 'user:logged-out',
  SUBSCRIPTION_CHANGED = 'subscription:changed',
  PAYMENT_COMPLETED = 'payment:completed',
  ROUTE_CHANGED = 'route:changed',
}
```

---

## 5. First Plugin: Wizard Flow

### 5.1 Wizard Plugin Overview

**Plugin Name:** `@vbwd/wizard-plugin`

**Responsibilities:**
- Multi-step form wizard for subscription signup
- File upload with validation
- GDPR consent management
- Tariff plan selection
- Checkout flow integration

### 5.2 Wizard Steps

```
Step 1: Upload & Description
  ├─ File upload (drag & drop, validation)
  ├─ Optional textarea for additional info
  └─ Client-side validation before proceeding

Step 2: User Info & GDPR
  ├─ Email address input
  ├─ GDPR consent checkbox (required)
  ├─ Privacy policy link
  └─ Backend validation (API call)

Step 3: Tariff Plan Selection
  ├─ Display 3 tariff plans from API
  ├─ Comparison table
  ├─ Plan selection (radio buttons)
  └─ Price display with billing period

Step 4: Checkout & Payment
  ├─ Order summary
  ├─ User details form (name, address)
  ├─ Payment method selection
  └─ Redirect to PayPal/Stripe

Step 5: Account Creation
  ├─ Create account (if new user)
  ├─ Set password
  └─ Redirect to user cabinet
```

### 5.3 Wizard Plugin Structure

```
src/plugins/wizard/
├── index.ts                  # Plugin entry point (implements IPlugin)
├── routes.ts                 # Route definitions
├── store/
│   ├── wizardStore.ts        # Wizard state (current step, form data)
│   └── types.ts
├── components/
│   ├── WizardContainer.vue   # Main wizard container
│   ├── WizardStep.vue        # Generic step component
│   ├── steps/
│   │   ├── StepUpload.vue
│   │   ├── StepGdpr.vue
│   │   ├── StepPlans.vue
│   │   ├── StepCheckout.vue
│   │   └── StepAccount.vue
│   └── shared/
│       ├── FileUpload.vue
│       ├── PlanCard.vue
│       └── ProgressIndicator.vue
├── composables/
│   ├── useWizard.ts          # Wizard navigation logic
│   ├── useFileUpload.ts      # File handling
│   └── useValidation.ts      # Step-specific validation
├── types/
│   └── wizard.types.ts
└── __tests__/
    ├── unit/
    │   └── wizardStore.spec.ts
    └── e2e/
        └── wizard-flow.spec.ts  # Playwright test
```

---

## 6. User Cabinet Plugin

### 6.1 Cabinet Plugin Overview

**Plugin Name:** `@vbwd/user-cabinet-plugin`

**Responsibilities:**
- User profile management
- Password change
- Address management
- Subscription management (view, upgrade, cancel)
- Invoice history
- Download invoices

### 6.2 Cabinet Plugin Structure

```
src/plugins/user-cabinet/
├── index.ts
├── routes.ts                 # Protected routes
├── store/
│   ├── userStore.ts
│   └── subscriptionStore.ts
├── components/
│   ├── CabinetLayout.vue
│   ├── profile/
│   │   ├── ProfileForm.vue
│   │   ├── PasswordChange.vue
│   │   └── AddressForm.vue
│   ├── subscriptions/
│   │   ├── SubscriptionList.vue
│   │   ├── SubscriptionCard.vue
│   │   └── UpgradeDialog.vue
│   └── invoices/
│       ├── InvoiceList.vue
│       └── InvoiceDownload.vue
├── composables/
│   ├── useProfile.ts
│   ├── useSubscriptions.ts
│   └── useInvoices.ts
└── __tests__/
    └── e2e/
        └── cabinet-flow.spec.ts
```

---

## 7. Access Control & Permissions

### 7.1 Route Guards

```typescript
// src/core/router/guards.ts
export const authGuard: NavigationGuard = (to, from, next) => {
  const authService = inject<IAuthService>('authService');

  if (to.meta.requiresAuth && !authService.isAuthenticated.value) {
    next({ name: 'login', query: { redirect: to.fullPath } });
  } else {
    next();
  }
};

export const planGuard: NavigationGuard = (to, from, next) => {
  const authService = inject<IAuthService>('authService');
  const requiredPlans = to.meta.requiredPlan as string[] | undefined;

  if (requiredPlans && !authService.canAccessPlan(requiredPlans[0])) {
    next({ name: 'upgrade', query: { plan: requiredPlans[0] } });
  } else {
    next();
  }
};
```

### 7.2 Component-Level Access Control

```vue
<!-- Using composable -->
<script setup lang="ts">
import { useAuth } from '@/core/auth';

const { hasPermission, canAccessPlan } = useAuth();
</script>

<template>
  <div>
    <button v-if="hasPermission('edit:profile')">
      Edit Profile
    </button>

    <div v-if="canAccessPlan('premium')">
      Premium Content
    </div>
  </div>
</template>
```

---

## 8. Directory Structure

```
frontend/user/vue/
├── src/
│   ├── core/                    # Core SDK layer
│   │   ├── api/
│   │   │   ├── ApiClient.ts     # Main API client
│   │   │   ├── IApiClient.ts    # Interface
│   │   │   ├── interceptors.ts  # Axios interceptors
│   │   │   └── types/           # Request/Response types
│   │   ├── auth/
│   │   │   ├── AuthService.ts
│   │   │   ├── IAuthService.ts
│   │   │   └── authStore.ts
│   │   ├── validation/
│   │   │   ├── ValidationService.ts
│   │   │   ├── IValidationService.ts
│   │   │   └── schemas/
│   │   ├── events/
│   │   │   ├── EventBus.ts
│   │   │   └── IEventBus.ts
│   │   ├── plugin/
│   │   │   ├── IPlugin.ts
│   │   │   ├── PluginRegistry.ts
│   │   │   └── PluginLoader.ts
│   │   ├── sdk/
│   │   │   └── PlatformSDK.ts
│   │   └── router/
│   │       ├── index.ts
│   │       └── guards.ts
│   │
│   ├── plugins/                 # All plugins
│   │   ├── wizard/
│   │   ├── user-cabinet/
│   │   └── admin-dashboard/
│   │
│   ├── shared/                  # Shared components & utilities
│   │   ├── components/          # Reusable UI components
│   │   │   ├── Button.vue
│   │   │   ├── Input.vue
│   │   │   ├── Modal.vue
│   │   │   └── Card.vue
│   │   ├── composables/         # Shared composables
│   │   │   ├── useNotification.ts
│   │   │   ├── useAsync.ts
│   │   │   └── useForm.ts
│   │   ├── utils/               # Utility functions
│   │   │   ├── format.ts
│   │   │   ├── validation.ts
│   │   │   └── storage.ts
│   │   └── types/               # Shared types
│   │       ├── api.types.ts
│   │       └── common.types.ts
│   │
│   ├── App.vue                  # Root component
│   ├── main.ts                  # Application entry point
│   └── env.d.ts                 # TypeScript environment definitions
│
├── tests/
│   ├── unit/                    # Vitest unit tests
│   │   ├── core/
│   │   └── plugins/
│   └── e2e/                     # Playwright E2E tests
│       ├── fixtures/
│       ├── flows/
│       │   ├── wizard.spec.ts
│       │   ├── cabinet.spec.ts
│       │   └── auth.spec.ts
│       └── playwright.config.ts
│
├── public/                      # Static assets
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.ts
├── playwright.config.ts
└── vitest.config.ts
```

---

## 9. Development Principles

### 9.1 Core Practices

- **TDD First**: Write Playwright E2E tests for user flows, Vitest unit tests for logic
- **SOLID Principles**: Single responsibility, Open-closed, Liskov substitution, Interface segregation, Dependency inversion
- **LSP**: All plugins implement IPlugin, all services implement interfaces
- **DI**: Services injected via Vue's `provide/inject` or Pinia stores
- **Type Safety**: Strict TypeScript mode, no `any` types
- **Clean Code**: ESLint + Prettier, meaningful names, small functions

### 9.2 Testing Strategy

```bash
# Unit tests (Vitest)
npm run test:unit

# Run specific test file
npm run test:unit src/core/api/ApiClient.spec.ts

# E2E tests (Playwright)
npm run test:e2e

# Run specific E2E test
npm run test:e2e tests/e2e/flows/wizard.spec.ts

# E2E with UI mode
npm run test:e2e:ui

# All tests
npm run test
```

**Test Coverage Requirements:**
- Core SDK: 90%+ coverage
- Plugins: 80%+ coverage
- E2E: All critical user flows

### 9.3 Plugin Development Workflow

1. **Define Plugin Interface**
   ```typescript
   export class MyPlugin implements IPlugin {
     name = 'my-plugin';
     version = '1.0.0';

     async install(app: App, sdk: PlatformSDK) {
       // Register routes, components, stores
     }
   }
   ```

2. **Write E2E Test First (TDD)**
   ```typescript
   test('user can complete wizard flow', async ({ page }) => {
     await page.goto('/wizard');
     // Test user flow
   });
   ```

3. **Implement Plugin**
   - Create components
   - Implement store logic
   - Add validation
   - Use SDK services

4. **Register Plugin**
   ```typescript
   // main.ts
   const pluginRegistry = new PluginRegistry();
   pluginRegistry.register(new WizardPlugin());
   await pluginRegistry.loadPlugin('wizard', sdk);
   ```

---

## 10. API Client Usage Examples

### 10.1 In Components

```vue
<script setup lang="ts">
import { ref } from 'vue';
import { useApi } from '@/core/api';

const api = useApi();
const plans = ref<TariffPlan[]>([]);
const loading = ref(false);

const loadPlans = async () => {
  loading.value = true;
  try {
    plans.value = await api.tariffs.list();
  } catch (error) {
    console.error('Failed to load plans:', error);
  } finally {
    loading.value = false;
  }
};

loadPlans();
</script>

<template>
  <div>
    <div v-if="loading">Loading plans...</div>
    <div v-else>
      <plan-card
        v-for="plan in plans"
        :key="plan.id"
        :plan="plan"
      />
    </div>
  </div>
</template>
```

### 10.2 In Stores

```typescript
// plugins/wizard/store/wizardStore.ts
import { defineStore } from 'pinia';
import { useApi } from '@/core/api';

export const useWizardStore = defineStore('wizard', () => {
  const api = useApi();
  const currentStep = ref(1);
  const formData = ref<WizardFormData>({});

  const submitWizard = async () => {
    // Use API client
    const result = await api.checkout.create({
      tariffPlanId: formData.value.selectedPlan,
      email: formData.value.email,
      gdprConsent: formData.value.gdprConsent,
    });

    return result;
  };

  return { currentStep, formData, submitWizard };
});
```

---

## 11. PlantUML Diagrams

All architecture diagrams are available in PlantUML format:

| Diagram                     | File                              | Description                       |
|-----------------------------|-----------------------------------|-----------------------------------|
| Plugin System Architecture  | `puml/plugin-architecture.puml`   | Plugin loading and lifecycle      |
| Wizard Flow                 | `puml/wizard-flow.puml`           | User journey through wizard       |
| Component Hierarchy         | `puml/component-tree.puml`        | Component structure               |
| State Management            | `puml/state-management.puml`      | Pinia stores and relationships    |
| API Client Architecture     | `puml/api-client.puml`            | HTTP client structure             |
| Route Guard Flow            | `puml/route-guards.puml`          | Authentication and authorization  |

---

## 12. Related Documentation

### Architecture Documents
- [Server Architecture](../architecture_server/README.md) - Flask API documentation
- [Sprint Plans](./sprints/README.md) - Frontend implementation sprints

### Other Documentation
- `docs/devlog/` - Daily development logs
- `CLAUDE.md` - Claude Code guidance
- `README.md` - Project overview
