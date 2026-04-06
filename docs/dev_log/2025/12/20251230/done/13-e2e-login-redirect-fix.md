# Sprint 13: E2E Login Redirect Bug Fix

## Problem Statement

9 out of 11 E2E Playwright tests are failing because login does not redirect to `/dashboard` after successful authentication. The page remains on `/login` even though the backend API returns a valid token.

## ROOT CAUSE IDENTIFIED

**Multiple ApiClient Instances**: Each store and component creates its own ApiClient instance. When Login.vue calls `api.setToken()`, it only sets the token on its local instance. Other stores (profile, subscription, invoices, plans) have separate instances without the token.

```
Login.vue       → new ApiClient() → setToken(token) ✓
profile.ts      → new ApiClient() → NO TOKEN ✗
subscription.ts → new ApiClient() → NO TOKEN ✗
invoices.ts     → new ApiClient() → NO TOKEN ✗
plans.ts        → new ApiClient() → NO TOKEN ✗
```

**Fix Required**: Create a shared/singleton ApiClient instance used by all stores and components.

## Test Results

| Test | Status | Issue |
|------|--------|-------|
| redirects to login when not authenticated | PASS | - |
| shows error with invalid credentials | PASS | - |
| can login with valid credentials | FAIL | Stays on `/login` instead of `/dashboard` |
| can logout | FAIL | Blocked by login failure |
| displays profile information | FAIL | Blocked by login failure |
| can update profile name | FAIL | Blocked by login failure |
| can change password | FAIL | Blocked by login failure |
| displays current subscription | FAIL | Blocked by login failure |
| shows usage statistics | FAIL | Blocked by login failure |
| can navigate to plan selection | FAIL | Blocked by login failure |
| can cancel subscription with confirmation | FAIL | Blocked by login failure |

## Root Cause Analysis

### Verified Working

1. **Backend API**: Login endpoint works correctly
   ```bash
   curl -X POST http://localhost:5000/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","password":"TestPass123@"}'

   # Returns: { "success": true, "token": "eyJ...", "user_id": "..." }
   ```

2. **Test Data**: User `test@example.com` exists in database (seeded by TestDataSeeder)

3. **E2E Infrastructure**: Playwright correctly fills form and clicks button

### Suspected Issue

The login flow in `Login.vue`:

```typescript
// Login.vue (lines 52-76)
async function handleLogin() {
  loading.value = true;
  error.value = '';

  try {
    const response = await api.post('/auth/login', {
      email: email.value,
      password: password.value
    }) as { success: boolean; token: string; user_id: string; error?: string };

    if (!response.success) {
      throw new Error(response.error || 'Login failed');
    }

    localStorage.setItem('auth_token', response.token);
    localStorage.setItem('user_id', response.user_id);
    api.setToken(response.token);

    router.push('/dashboard');  // <-- This line is not executing or failing silently
  } catch (err) {
    error.value = (err as Error).message || 'Invalid credentials';
  } finally {
    loading.value = false;
  }
}
```

### Potential Causes

1. **ApiClient Error Handling**: The `ApiClient.post()` method may throw an error even on successful responses if there's a type mismatch or parsing issue

2. **Router Navigation Guard Race Condition**: The navigation guard checks `localStorage.getItem('auth_token')` but the token might not be persisted yet

3. **Proxy Configuration**: The Vite proxy may be modifying or blocking responses

4. **CORS Issues**: Browser may block the response due to CORS headers

5. **Response Format Mismatch**: Backend response structure may not match what frontend expects

## Investigation Tasks

### Phase 1: Diagnostic (TDD Approach)

1. **Add E2E test with network inspection**
   ```typescript
   // tests/e2e/auth-debug.spec.ts
   test('login API returns correct response', async ({ page }) => {
     const responsePromise = page.waitForResponse('**/auth/login');

     await page.goto('/login');
     await page.fill('[data-testid="email"]', 'test@example.com');
     await page.fill('[data-testid="password"]', 'TestPass123@');
     await page.click('[data-testid="login-button"]');

     const response = await responsePromise;
     const body = await response.json();

     expect(response.status()).toBe(200);
     expect(body.success).toBe(true);
     expect(body.token).toBeDefined();
   });

   test('localStorage is set after login', async ({ page }) => {
     await page.goto('/login');
     await page.fill('[data-testid="email"]', 'test@example.com');
     await page.fill('[data-testid="password"]', 'TestPass123@');
     await page.click('[data-testid="login-button"]');

     // Wait for potential async operations
     await page.waitForTimeout(1000);

     const token = await page.evaluate(() => localStorage.getItem('auth_token'));
     expect(token).toBeTruthy();
   });
   ```

2. **Add console logging to Login.vue** (temporary debug)
   ```typescript
   async function handleLogin() {
     console.log('[Login] Starting login...');
     try {
       const response = await api.post('/auth/login', {...});
       console.log('[Login] Response:', response);

       localStorage.setItem('auth_token', response.token);
       console.log('[Login] Token stored:', localStorage.getItem('auth_token'));

       router.push('/dashboard');
       console.log('[Login] Navigation triggered');
     } catch (err) {
       console.error('[Login] Error:', err);
       error.value = (err as Error).message;
     }
   }
   ```

### Phase 2: Fix Implementation

Based on investigation results, implement one of these fixes:

#### Option A: Async Router Navigation

```typescript
// If router.push is not awaited properly
async function handleLogin() {
  try {
    const response = await api.post('/auth/login', {...});

    if (!response.success) {
      throw new Error(response.error || 'Login failed');
    }

    localStorage.setItem('auth_token', response.token);
    localStorage.setItem('user_id', response.user_id);
    api.setToken(response.token);

    // Await the navigation
    await router.push('/dashboard');
  } catch (err) {
    error.value = (err as Error).message || 'Invalid credentials';
  }
}
```

#### Option B: Navigation Guard Timing Fix

```typescript
// router/index.ts - Add nextTick or timeout
router.beforeEach(async (to, _from, next) => {
  // Wait for localStorage to be updated
  await new Promise(resolve => setTimeout(resolve, 0));

  const isAuthenticated = localStorage.getItem('auth_token');
  // ... rest of guard
});
```

#### Option C: ApiClient Response Handling Fix

```typescript
// If ApiClient is throwing on valid responses
async post<T>(url: string, data?: unknown): Promise<T> {
  try {
    const response = await this.axiosInstance.post<T>(url, data);
    return response.data;
  } catch (error) {
    // Don't throw on 2xx responses
    if (axios.isAxiosError(error) && error.response?.status < 400) {
      return error.response.data as T;
    }
    throw ApiError.fromAxiosError(error);
  }
}
```

#### Option D: Use Pinia Auth Store

```typescript
// Centralize auth logic in a store
// stores/auth.ts
export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: localStorage.getItem('auth_token'),
    userId: localStorage.getItem('user_id'),
  }),

  actions: {
    async login(email: string, password: string) {
      const response = await api.post('/auth/login', { email, password });

      if (!response.success) {
        throw new Error(response.error);
      }

      this.token = response.token;
      this.userId = response.user_id;
      localStorage.setItem('auth_token', response.token);
      localStorage.setItem('user_id', response.user_id);

      return true;
    }
  }
});

// Login.vue
const authStore = useAuthStore();
await authStore.login(email.value, password.value);
router.push('/dashboard');
```

## Files to Modify

| File | Action |
|------|--------|
| `user/vue/src/api/index.ts` | **CREATE** - Shared ApiClient singleton |
| `user/vue/src/views/Login.vue` | **UPDATE** - Use shared api instance |
| `user/vue/src/stores/profile.ts` | **UPDATE** - Use shared api instance |
| `user/vue/src/stores/subscription.ts` | **UPDATE** - Use shared api instance |
| `user/vue/src/stores/invoices.ts` | **UPDATE** - Use shared api instance |
| `user/vue/src/stores/plans.ts` | **UPDATE** - Use shared api instance |

## Implementation Plan

### Step 1: Create Shared API Instance (TDD)

**Test First**: `user/vue/tests/unit/api/shared-api.spec.ts`
```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { api, initializeApi } from '@/api';

describe('Shared API Instance', () => {
  it('exports a singleton ApiClient instance', () => {
    expect(api).toBeDefined();
    expect(api.baseURL).toBe('/api');
  });

  it('setToken persists across imports', async () => {
    api.setToken('test-token');

    // Re-import to verify singleton
    const { api: api2 } = await import('@/api');
    expect(api2.getToken()).toBe('test-token');
  });

  it('initializes token from localStorage', () => {
    localStorage.setItem('auth_token', 'stored-token');
    initializeApi();
    expect(api.getToken()).toBe('stored-token');
  });
});
```

**Implementation**: `user/vue/src/api/index.ts`
```typescript
import { ApiClient } from '@vbwd/view-component';

// Singleton API client instance
export const api = new ApiClient({
  baseURL: import.meta.env.VITE_API_URL || '/api'
});

// Initialize token from localStorage if present
export function initializeApi(): void {
  const token = localStorage.getItem('auth_token');
  if (token) {
    api.setToken(token);
  }
}

// Initialize on module load
initializeApi();
```

### Step 2: Update Login.vue

```typescript
// BEFORE
import { ApiClient } from '@vbwd/view-component';
const api = new ApiClient({ baseURL: '/api' });

// AFTER
import { api } from '@/api';
```

### Step 3: Update All Stores

```typescript
// BEFORE (in each store)
import { ApiClient } from '@vbwd/view-component';
const api = new ApiClient({ baseURL: '/api' });

// AFTER
import { api } from '@/api';
```

### Step 4: Initialize API in main.ts

```typescript
// main.ts
import { initializeApi } from '@/api';

// Initialize API with stored token before mounting app
initializeApi();

app.mount('#app');
```

## Acceptance Criteria

1. All 11 E2E tests pass
2. Login redirects to `/dashboard` after successful authentication
3. Token is stored in localStorage
4. Navigation guard correctly allows access to protected routes
5. No regression in existing functionality

## Testing Strategy

1. **Unit Tests**: Add tests for auth store login action
2. **Integration Tests**: Test ApiClient with mock server
3. **E2E Tests**: All existing tests must pass

## SOLID Principles

- **Single Responsibility**: Auth logic should be in a dedicated store, not in the component
- **Open/Closed**: ApiClient error handling should be extensible
- **Dependency Inversion**: Login.vue should depend on auth abstraction, not direct API calls

## Estimated Complexity

- Investigation: Medium
- Fix Implementation: Low-Medium (depends on root cause)
- Testing: Low

## Dependencies

- Backend must be running (`make up` in vbwd-backend)
- Test data must be seeded
- Playwright browsers installed
