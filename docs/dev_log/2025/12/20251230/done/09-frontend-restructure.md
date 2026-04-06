# Sprint 09: Frontend User App Restructure

**Priority:** HIGH (Blocker for Sprint 06)
**Duration:** 0.5 day
**Focus:** Set up proper user app structure, Playwright e2e, package alignment

> **Core Requirements:** TDD-first, SOLID, Liskov, DI, Clean Code

---

## 9.1 Package Naming Alignment

### Problem
- Core package: `@vbwd/view-component`
- User/Admin apps reference: `@vbwd/core-sdk`

### Solution
Update user and admin package.json to use `@vbwd/view-component`.

### Files to Update
- `vbwd-frontend/user/package.json`
- `vbwd-frontend/admin/vue/package.json`

### TDD Tests First

**File:** `vbwd-frontend/core/tests/unit/package-imports.spec.ts`
```typescript
import { describe, it, expect } from 'vitest';

describe('Package Exports', () => {
  it('exports core SDK components', async () => {
    const sdk = await import('@vbwd/view-component');
    expect(sdk.name).toBe('@vbwd/view-component');
    expect(sdk.version).toBeDefined();
  });

  it('exports plugin system', async () => {
    const { PluginRegistry, PlatformSDK } = await import('@vbwd/view-component');
    expect(PluginRegistry).toBeDefined();
    expect(PlatformSDK).toBeDefined();
  });

  it('exports UI components', async () => {
    const { Button, Input, Card, Modal } = await import('@vbwd/view-component');
    expect(Button).toBeDefined();
    expect(Input).toBeDefined();
    expect(Card).toBeDefined();
    expect(Modal).toBeDefined();
  });
});
```

---

## 9.2 User App Main Structure

### Problem
User app only has wizard plugin, no main app structure.

### Solution
Create main app with:
- `src/` - Main application source
- `src/views/` - Page components
- `src/stores/` - Pinia stores
- `src/router/` - Vue Router config
- `src/layouts/` - Layout components
- `plugin/` - Optional plugins (wizard_form stays here)

### Directory Structure
```
vbwd-frontend/user/
├── package.json
├── vite.config.js
├── vitest.config.js
├── playwright.config.ts          # NEW: E2E config
├── vue/
│   ├── index.html
│   ├── src/
│   │   ├── App.vue               # Main app component
│   │   ├── main.ts               # Entry point
│   │   ├── router/
│   │   │   └── index.ts          # Router config
│   │   ├── stores/
│   │   │   ├── profile.ts        # Profile store
│   │   │   ├── subscription.ts   # Subscription store
│   │   │   ├── invoices.ts       # Invoices store
│   │   │   └── plans.ts          # Plans store
│   │   ├── views/
│   │   │   ├── Profile.vue       # Profile page
│   │   │   ├── Subscription.vue  # Subscription page
│   │   │   ├── Invoices.vue      # Invoices page
│   │   │   ├── Plans.vue         # Plans page
│   │   │   └── Dashboard.vue     # Dashboard page
│   │   └── layouts/
│   │       └── UserLayout.vue    # Main layout with sidebar
│   ├── tests/
│   │   ├── unit/                 # Unit tests
│   │   │   └── stores/
│   │   └── e2e/                  # Playwright e2e tests
│   │       ├── auth.spec.ts
│   │       ├── profile.spec.ts
│   │       ├── subscription.spec.ts
│   │       └── fixtures/
│   └── plugin/
│       └── wizzard_form/         # Existing wizard plugin
```

### TDD Tests First

**File:** `vbwd-frontend/user/vue/tests/unit/stores/profile.spec.ts`
```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { useProfileStore } from '../../../src/stores/profile';

describe('ProfileStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('initializes with empty profile', () => {
    const store = useProfileStore();
    expect(store.profile).toBeNull();
    expect(store.loading).toBe(false);
    expect(store.error).toBeNull();
  });

  it('fetches profile from API', async () => {
    const store = useProfileStore();
    // Mock API call
    vi.spyOn(store, 'fetchProfile').mockResolvedValue({
      id: '1',
      name: 'John Doe',
      email: 'john@example.com'
    });

    await store.fetchProfile();
    expect(store.profile).not.toBeNull();
  });

  it('handles fetch error gracefully', async () => {
    const store = useProfileStore();
    vi.spyOn(store, 'fetchProfile').mockRejectedValue(new Error('Network error'));

    await store.fetchProfile();
    expect(store.error).toBe('Network error');
  });

  it('updates profile with valid data', async () => {
    const store = useProfileStore();
    store.profile = { id: '1', name: 'John', email: 'john@example.com' };

    await store.updateProfile({ name: 'Jane' });
    expect(store.profile.name).toBe('Jane');
  });

  it('changes password with current password validation', async () => {
    const store = useProfileStore();

    const result = await store.changePassword('oldpass', 'newpass');
    expect(result.success).toBeDefined();
  });
});
```

---

## 9.3 Playwright E2E Setup

### Problem
No e2e tests configured.

### Solution
Set up Playwright with per-app tests.

### Files to Create

**File:** `vbwd-frontend/user/playwright.config.ts`
```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './vue/tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
});
```

**File:** `vbwd-frontend/user/vue/tests/e2e/auth.spec.ts`
```typescript
import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('redirects to login when not authenticated', async ({ page }) => {
    await page.goto('/profile');
    await expect(page).toHaveURL(/.*login/);
  });

  test('can login with valid credentials', async ({ page }) => {
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');

    await expect(page).toHaveURL('/dashboard');
  });

  test('shows error with invalid credentials', async ({ page }) => {
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'wrongpassword');
    await page.click('[data-testid="login-button"]');

    await expect(page.locator('[data-testid="error-message"]')).toBeVisible();
  });

  test('can logout', async ({ page }) => {
    // First login
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');

    // Then logout
    await page.click('[data-testid="user-menu"]');
    await page.click('[data-testid="logout-button"]');

    await expect(page).toHaveURL(/.*login/);
  });
});
```

**File:** `vbwd-frontend/user/vue/tests/e2e/profile.spec.ts`
```typescript
import { test, expect } from '@playwright/test';

test.describe('Profile Management', () => {
  test.beforeEach(async ({ page }) => {
    // Login before each test
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');
    await page.waitForURL('/dashboard');
  });

  test('displays profile information', async ({ page }) => {
    await page.goto('/profile');

    await expect(page.locator('[data-testid="profile-name"]')).toBeVisible();
    await expect(page.locator('[data-testid="profile-email"]')).toBeVisible();
  });

  test('can update profile name', async ({ page }) => {
    await page.goto('/profile');

    await page.fill('[data-testid="name-input"]', 'New Name');
    await page.click('[data-testid="save-profile"]');

    await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();
  });

  test('can change password', async ({ page }) => {
    await page.goto('/profile');

    await page.fill('[data-testid="current-password"]', 'password123');
    await page.fill('[data-testid="new-password"]', 'newpassword456');
    await page.fill('[data-testid="confirm-password"]', 'newpassword456');
    await page.click('[data-testid="change-password"]');

    await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();
  });
});
```

**File:** `vbwd-frontend/user/vue/tests/e2e/subscription.spec.ts`
```typescript
import { test, expect } from '@playwright/test';

test.describe('Subscription Management', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');
    await page.waitForURL('/dashboard');
  });

  test('displays current subscription', async ({ page }) => {
    await page.goto('/subscription');

    await expect(page.locator('[data-testid="plan-name"]')).toBeVisible();
    await expect(page.locator('[data-testid="plan-status"]')).toBeVisible();
  });

  test('shows usage statistics', async ({ page }) => {
    await page.goto('/subscription');

    await expect(page.locator('[data-testid="usage-api"]')).toBeVisible();
    await expect(page.locator('[data-testid="usage-storage"]')).toBeVisible();
  });

  test('can navigate to plan selection', async ({ page }) => {
    await page.goto('/subscription');
    await page.click('[data-testid="change-plan"]');

    await expect(page).toHaveURL('/plans');
  });

  test('can cancel subscription with confirmation', async ({ page }) => {
    await page.goto('/subscription');
    await page.click('[data-testid="cancel-subscription"]');

    // Confirmation modal appears
    await expect(page.locator('[data-testid="cancel-modal"]')).toBeVisible();
    await page.click('[data-testid="confirm-cancel"]');

    await expect(page.locator('[data-testid="cancellation-notice"]')).toBeVisible();
  });
});
```

---

## 9.4 Package.json Updates

### User App Package.json

**File:** `vbwd-frontend/user/package.json`
```json
{
  "name": "vbwd-user",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc --noEmit && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "lint": "eslint . --ext .vue,.js,.jsx,.cjs,.mjs,.ts,.tsx --fix"
  },
  "dependencies": {
    "@vbwd/view-component": "file:../core",
    "vue": "^3.4.0",
    "vue-router": "^4.2.5",
    "pinia": "^2.1.7",
    "socket.io-client": "^4.7.2"
  },
  "devDependencies": {
    "@playwright/test": "^1.40.0",
    "@vitejs/plugin-vue": "^4.5.2",
    "@vue/test-utils": "^2.4.0",
    "happy-dom": "^12.0.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.8",
    "vitest": "^1.1.0",
    "vue-tsc": "^1.8.0",
    "eslint": "^8.56.0",
    "eslint-plugin-vue": "^9.19.2"
  }
}
```

---

## Checklist

### 9.1 Package Naming
- [ ] Update user/package.json to @vbwd/view-component
- [ ] Update admin/package.json to @vbwd/view-component
- [ ] Verify imports work correctly
- [ ] Run npm install in both apps

### 9.2 User App Structure
- [ ] Create src/main.ts entry point
- [ ] Create src/App.vue
- [ ] Create src/router/index.ts
- [ ] Create src/stores/ directory
- [ ] Create src/views/ directory
- [ ] Create src/layouts/ directory
- [ ] Update vite.config.js

### 9.3 Playwright Setup
- [ ] Add @playwright/test dependency
- [ ] Create playwright.config.ts
- [ ] Create tests/e2e/ directory
- [ ] Create auth.spec.ts
- [ ] Create profile.spec.ts
- [ ] Create subscription.spec.ts

### 9.4 Verification
- [ ] npm run test passes
- [ ] npm run dev starts successfully
- [ ] npm run build completes
- [ ] npm run test:e2e runs (may fail pending implementation)

---

## Verification Commands

```bash
# Install dependencies
cd vbwd-frontend/user && npm install

# Run unit tests
npm run test

# Run e2e tests
npm run test:e2e

# Start dev server
npm run dev
```
