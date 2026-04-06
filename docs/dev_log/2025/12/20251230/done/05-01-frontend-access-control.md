# Sprint 05-01: Frontend Access Control

**Priority:** HIGH
**Duration:** 1 day
**Focus:** Implement frontend route guards and feature gating components
**Depends On:** Sprint 05 (View Core Extraction)

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

> **Note:** This sprint was split from Sprint 04. Backend RBAC and permission decorators are in [Sprint 04](./04-access-control.md).

---

## Prerequisites

Before starting this sprint, ensure:
- [ ] Sprint 05 complete - `@vbwd/view-component` package published
- [ ] Sprint 04 complete - Backend RBAC and FeatureGuard services working
- [ ] API endpoints for permissions and features available

---

## 05-01.1 Route Guards

### Problem
No frontend route guards for authentication or role-based access.

### Requirements
- Authentication guard (redirect to login if not authenticated)
- Role guard (check user roles against route requirements)
- Guest guard (redirect away from login if already authenticated)

### TDD Tests First

**File:** `@vbwd/view-component` → `tests/unit/guards/AuthGuard.spec.ts`
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { authGuard } from '@/guards/AuthGuard';

describe('AuthGuard', () => {
  it('should allow access when user is authenticated', () => {
    // Test implementation
  });

  it('should redirect to login when not authenticated', () => {
    // Test implementation
  });

  it('should redirect away from guest routes when authenticated', () => {
    // Test implementation
  });

  it('should pass redirect query param to login', () => {
    // Test implementation
  });
});
```

**File:** `@vbwd/view-component` → `tests/unit/guards/RoleGuard.spec.ts`
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { roleGuard } from '@/guards/RoleGuard';

describe('RoleGuard', () => {
  it('should allow access when user has required role', () => {
    // Test implementation
  });

  it('should deny access when user lacks required role', () => {
    // Test implementation
  });

  it('should allow access when no roles required', () => {
    // Test implementation
  });

  it('should allow access when user has any of multiple roles', () => {
    // Test implementation
  });
});
```

### Implementation

**File:** `@vbwd/view-component` → `src/guards/AuthGuard.ts`
```typescript
import type { RouteLocationNormalized, NavigationGuardNext } from 'vue-router';
import { useAuthStore } from '../stores/auth';

export function authGuard(
  to: RouteLocationNormalized,
  from: RouteLocationNormalized,
  next: NavigationGuardNext
): void {
  const auth = useAuthStore();

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    next({ name: 'login', query: { redirect: to.fullPath } });
    return;
  }

  if (to.meta.requiresGuest && auth.isAuthenticated) {
    next({ name: 'dashboard' });
    return;
  }

  next();
}
```

**File:** `@vbwd/view-component` → `src/guards/RoleGuard.ts`
```typescript
import type { RouteLocationNormalized, NavigationGuardNext } from 'vue-router';
import { useAuthStore } from '../stores/auth';

export function roleGuard(
  to: RouteLocationNormalized,
  from: RouteLocationNormalized,
  next: NavigationGuardNext
): void {
  const auth = useAuthStore();
  const requiredRoles = to.meta.roles as string[] | undefined;

  if (!requiredRoles || requiredRoles.length === 0) {
    next();
    return;
  }

  const userRoles = auth.user?.roles || [];
  const hasRole = requiredRoles.some(role => userRoles.includes(role));

  if (!hasRole) {
    next({ name: 'forbidden' });
    return;
  }

  next();
}
```

**File:** `@vbwd/view-component` → `src/guards/index.ts`
```typescript
export { authGuard } from './AuthGuard';
export { roleGuard } from './RoleGuard';
```

---

## 05-01.2 Feature Access Composable

### Problem
No way to check feature access or usage limits in components.

### Requirements
- Check if user can access a feature
- Get feature usage statistics
- Check if user is within usage limits

### TDD Tests First

**File:** `@vbwd/view-component` → `tests/unit/composables/useFeatureAccess.spec.ts`
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useFeatureAccess } from '@/composables/useFeatureAccess';

describe('useFeatureAccess', () => {
  it('should return true when user has feature access', () => {
    // Test implementation
  });

  it('should return false when user lacks feature access', () => {
    // Test implementation
  });

  it('should return correct usage statistics', () => {
    // Test implementation
  });

  it('should check usage limits correctly', () => {
    // Test implementation
  });
});
```

### Implementation

**File:** `@vbwd/view-component` → `src/composables/useFeatureAccess.ts`
```typescript
import { computed } from 'vue';
import { useSubscriptionStore } from '../stores/subscription';

export function useFeatureAccess() {
  const subscription = useSubscriptionStore();

  const canAccess = (featureName: string): boolean => {
    return subscription.features.includes(featureName);
  };

  const getUsage = (featureName: string) => {
    return subscription.usage[featureName] || { limit: 0, used: 0, remaining: 0 };
  };

  const isWithinLimit = (featureName: string, amount: number = 1): boolean => {
    const usage = getUsage(featureName);
    return usage.remaining >= amount;
  };

  return {
    canAccess,
    getUsage,
    isWithinLimit,
    features: computed(() => subscription.features),
    usage: computed(() => subscription.usage),
  };
}
```

---

## 05-01.3 FeatureGate Component

### Problem
No declarative way to conditionally render UI based on feature access.

### Requirements
- Show content only if user has feature access
- Show fallback/upgrade prompt if no access
- Emit upgrade event for handling

### TDD Tests First

**File:** `@vbwd/view-component` → `tests/unit/components/FeatureGate.spec.ts`
```typescript
import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import FeatureGate from '@/components/FeatureGate.vue';

describe('FeatureGate', () => {
  it('should render slot content when user has access', () => {
    // Test implementation
  });

  it('should render fallback when user lacks access', () => {
    // Test implementation
  });

  it('should emit upgrade event when upgrade button clicked', () => {
    // Test implementation
  });

  it('should show required plan name in fallback', () => {
    // Test implementation
  });
});
```

### Implementation

**File:** `@vbwd/view-component` → `src/components/FeatureGate.vue`
```vue
<template>
  <slot v-if="hasAccess" />
  <slot v-else name="fallback">
    <div class="vbwd-feature-locked">
      <p>This feature requires {{ requiredPlan || 'an upgraded' }} plan</p>
      <button class="vbwd-btn vbwd-btn-primary" @click="$emit('upgrade')">
        Upgrade Now
      </button>
    </div>
  </slot>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useFeatureAccess } from '../composables/useFeatureAccess';

const props = defineProps<{
  feature: string;
  requiredPlan?: string;
}>();

defineEmits<{
  upgrade: [];
}>();

const { canAccess } = useFeatureAccess();
const hasAccess = computed(() => canAccess(props.feature));
</script>

<style scoped>
.vbwd-feature-locked {
  padding: 1.5rem;
  text-align: center;
  background: var(--vbwd-color-surface, #f9fafb);
  border: 1px dashed var(--vbwd-color-border, #e5e7eb);
  border-radius: var(--vbwd-radius, 0.5rem);
}

.vbwd-feature-locked p {
  margin-bottom: 1rem;
  color: var(--vbwd-color-text-muted, #6b7280);
}
</style>
```

---

## 05-01.4 UsageLimit Component

### Problem
No way to display feature usage limits to users.

### Requirements
- Show current usage vs limit
- Visual progress indicator
- Warning when approaching limit

### Implementation

**File:** `@vbwd/view-component` → `src/components/UsageLimit.vue`
```vue
<template>
  <div :class="['vbwd-usage-limit', { 'vbwd-usage-warning': isNearLimit }]">
    <div class="vbwd-usage-header">
      <span class="vbwd-usage-label">{{ label }}</span>
      <span class="vbwd-usage-count">{{ used }} / {{ limit }}</span>
    </div>
    <div class="vbwd-usage-bar">
      <div class="vbwd-usage-progress" :style="{ width: percentage + '%' }" />
    </div>
    <p v-if="isNearLimit" class="vbwd-usage-warning-text">
      {{ warningMessage || 'Approaching limit' }}
    </p>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useFeatureAccess } from '../composables/useFeatureAccess';

const props = defineProps<{
  feature: string;
  label?: string;
  warningThreshold?: number;
  warningMessage?: string;
}>();

const { getUsage } = useFeatureAccess();

const usage = computed(() => getUsage(props.feature));
const used = computed(() => usage.value.used);
const limit = computed(() => usage.value.limit);
const remaining = computed(() => usage.value.remaining);

const percentage = computed(() => {
  if (limit.value === 0) return 0;
  return Math.min(100, (used.value / limit.value) * 100);
});

const isNearLimit = computed(() => {
  const threshold = props.warningThreshold ?? 0.8;
  return percentage.value >= threshold * 100;
});
</script>

<style scoped>
.vbwd-usage-limit {
  padding: 0.75rem;
  background: var(--vbwd-color-surface, #f9fafb);
  border-radius: var(--vbwd-radius, 0.5rem);
}

.vbwd-usage-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.5rem;
  font-size: 0.875rem;
}

.vbwd-usage-label {
  font-weight: 500;
}

.vbwd-usage-count {
  color: var(--vbwd-color-text-muted, #6b7280);
}

.vbwd-usage-bar {
  height: 0.5rem;
  background: var(--vbwd-color-border, #e5e7eb);
  border-radius: 9999px;
  overflow: hidden;
}

.vbwd-usage-progress {
  height: 100%;
  background: var(--vbwd-color-primary, #3b82f6);
  transition: width 0.3s ease;
}

.vbwd-usage-warning .vbwd-usage-progress {
  background: var(--vbwd-color-warning, #f59e0b);
}

.vbwd-usage-warning-text {
  margin-top: 0.5rem;
  font-size: 0.75rem;
  color: var(--vbwd-color-warning, #f59e0b);
}
</style>
```

---

## 05-01.5 Integration with Apps

### Usage in frontend/user

**File:** `vbwd-frontend/user/vue/src/router/index.ts`
```typescript
import { createRouter, createWebHistory } from 'vue-router';
import { authGuard, roleGuard } from '@vbwd/view-component';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/Login.vue'),
      meta: { requiresGuest: true }
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: () => import('../views/Dashboard.vue'),
      meta: { requiresAuth: true }
    },
    {
      path: '/premium-feature',
      name: 'premium',
      component: () => import('../views/PremiumFeature.vue'),
      meta: { requiresAuth: true }
    }
  ]
});

router.beforeEach(authGuard);

export default router;
```

**Example usage in component:**
```vue
<template>
  <div>
    <h1>Dashboard</h1>

    <FeatureGate feature="advanced_analytics" required-plan="Pro">
      <AnalyticsWidget />
    </FeatureGate>

    <UsageLimit feature="api_calls" label="API Calls" />
  </div>
</template>

<script setup>
import { FeatureGate, UsageLimit } from '@vbwd/view-component';
import AnalyticsWidget from './AnalyticsWidget.vue';
</script>
```

### Usage in frontend/admin

```typescript
import { authGuard, roleGuard } from '@vbwd/view-component';

// Apply both guards
router.beforeEach((to, from, next) => {
  authGuard(to, from, (result) => {
    if (result !== undefined) {
      next(result);
      return;
    }
    roleGuard(to, from, next);
  });
});
```

---

## Checklist

### 05-01.1 Route Guards
- [ ] Tests for AuthGuard
- [ ] Tests for RoleGuard
- [ ] AuthGuard implemented
- [ ] RoleGuard implemented
- [ ] Guards exported from index.ts
- [ ] All tests pass

### 05-01.2 Feature Access Composable
- [ ] Tests for useFeatureAccess
- [ ] useFeatureAccess implemented
- [ ] Exported from composables/index.ts
- [ ] All tests pass

### 05-01.3 FeatureGate Component
- [ ] Tests for FeatureGate
- [ ] FeatureGate component implemented
- [ ] Exported from components/index.ts
- [ ] All tests pass

### 05-01.4 UsageLimit Component
- [ ] Tests for UsageLimit
- [ ] UsageLimit component implemented
- [ ] Exported from components/index.ts
- [ ] All tests pass

### 05-01.5 App Integration
- [ ] frontend/user router uses guards
- [ ] frontend/admin router uses guards
- [ ] FeatureGate used in components
- [ ] UsageLimit used where appropriate

---

## Verification Commands

```bash
# Run guard tests in view-component repo
cd vbwd-view-component
npm run test -- tests/unit/guards/
npm run test -- tests/unit/composables/useFeatureAccess.spec.ts
npm run test -- tests/unit/components/FeatureGate.spec.ts

# Build and publish new version
npm run build
npm version patch
npm publish

# Update apps
cd vbwd-frontend/user/vue
npm update @vbwd/view-component
npm run dev

cd vbwd-frontend/admin/vue
npm update @vbwd/view-component
npm run dev
```

---

## Related Documentation

- [Sprint 04 - Backend Access Control](./04-access-control.md)
- [Sprint 05 - View Core Extraction](./05-ui-components.md)
- [Core View SDK Architecture](/docs/architecture_core_view_sdk/README.md)
