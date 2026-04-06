# Sprint 13 Completion Report: E2E Login Redirect Fix

**Status**: COMPLETED
**Date**: 2025-12-30

---

## Executive Summary

Fixed the E2E login redirect issue caused by multiple ApiClient instances not sharing the authentication token. Implemented a shared singleton API client pattern.

---

## Results

### Before
| Test Suite | Passed | Failed |
|------------|--------|--------|
| Authentication | 2 | 2 |
| Profile | 0 | 3 |
| Subscription | 0 | 4 |
| **Total** | **2** | **9** |

### After
| Test Suite | Passed | Failed |
|------------|--------|--------|
| Authentication | 4 | 0 |
| Profile | 0 | 3 |
| Subscription | 4 | 0 |
| **Total** | **8** | **3** |

**Improvement: +6 tests passing (73% pass rate)**

---

## Root Cause

Multiple ApiClient instances were being created across the application:

```
Login.vue       → new ApiClient() → setToken(token) ✓
profile.ts      → new ApiClient() → NO TOKEN ✗
subscription.ts → new ApiClient() → NO TOKEN ✗
invoices.ts     → new ApiClient() → NO TOKEN ✗
plans.ts        → new ApiClient() → NO TOKEN ✗
```

When login set the token, only its local instance received it. Other stores made unauthenticated requests.

---

## Solution

### 1. Created Shared API Singleton

**File**: `user/vue/src/api/index.ts`
```typescript
import { ApiClient } from '@vbwd/view-component';

export const api = new ApiClient({
  baseURL: import.meta.env.VITE_API_URL || '/api/v1'
});

export function initializeApi(): void {
  const token = localStorage.getItem('auth_token');
  if (token) {
    api.setToken(token);
  }
}

initializeApi();
```

### 2. Updated All Consumers

All stores and Login.vue now import from the shared instance:
```typescript
import { api } from '@/api';
```

### 3. Fixed Additional Issues

- **API baseURL**: Changed from `/api` to `/api/v1` (backend expects `/api/v1/*`)
- **Rate Limiting**: Configured Playwright to run serially (1 worker) to avoid hitting login rate limits (3/min)
- **Profile Store**: Added response mapping for backend format `{ user, details }` → `{ id, name, email }`

---

## Files Modified

| File | Action |
|------|--------|
| `user/vue/src/api/index.ts` | **CREATED** - Shared API singleton |
| `user/vue/src/views/Login.vue` | Updated import |
| `user/vue/src/stores/profile.ts` | Updated import + response mapping |
| `user/vue/src/stores/subscription.ts` | Updated import |
| `user/vue/src/stores/invoices.ts` | Updated import |
| `user/vue/src/stores/plans.ts` | Updated import |
| `user/vue/src/main.ts` | Added initializeApi() call |
| `user/playwright.config.ts` | Set workers=1, fullyParallel=false |

---

## Remaining Issues

3 profile tests still fail due to a **backend bug**:
- `/api/v1/user/profile` returns HTTP 500 "Internal Server Error"
- This is tracked in Sprint 14

---

## Verification

```bash
cd vbwd-frontend
make test-e2e

# Results: 8 passed, 3 failed (1.2m)
```

---

## SOLID Principles Applied

- **Single Responsibility**: API client management centralized in one module
- **Open/Closed**: Singleton extensible via initializeApi() without modifying consumers
- **Dependency Inversion**: All components depend on shared abstraction, not concrete instances
