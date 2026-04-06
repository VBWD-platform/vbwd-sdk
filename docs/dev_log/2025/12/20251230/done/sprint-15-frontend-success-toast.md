# Sprint 15: Frontend Success Toast Notifications

## Problem Statement

2 E2E tests fail because the frontend doesn't show success notifications after profile operations:

1. `can update profile name` - expects `[data-testid="success-toast"]` after save
2. `can change password` - expects `[data-testid="success-toast"]` after password change

## Current Test Expectations

```typescript
// profile.spec.ts:20 - can update profile name
await page.fill('[data-testid="name-input"]', 'New Name');
await page.click('[data-testid="save-profile"]');
await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();

// profile.spec.ts:29 - can change password
await page.fill('[data-testid="current-password"]', 'TestPass123@');
await page.fill('[data-testid="new-password"]', 'NewTestPass123@');
await page.click('[data-testid="change-password"]');
await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();
```

## Files to Modify

| File | Action |
|------|--------|
| `user/vue/src/components/ToastNotification.vue` | Create toast component |
| `user/vue/src/composables/useToast.ts` | Create toast composable |
| `user/vue/src/views/Profile.vue` | Add toast on success |
| `user/vue/src/App.vue` | Add toast container |

## Implementation Plan

### Step 1: Create Toast Component

```vue
<!-- ToastNotification.vue -->
<template>
  <Teleport to="body">
    <div
      v-if="visible"
      :data-testid="type + '-toast'"
      class="toast"
      :class="type"
    >
      {{ message }}
    </div>
  </Teleport>
</template>
```

### Step 2: Create Toast Composable

```typescript
// useToast.ts
import { ref } from 'vue';

const message = ref('');
const type = ref<'success' | 'error'>('success');
const visible = ref(false);

export function useToast() {
  function show(msg: string, toastType: 'success' | 'error' = 'success') {
    message.value = msg;
    type.value = toastType;
    visible.value = true;
    setTimeout(() => { visible.value = false; }, 3000);
  }

  return { message, type, visible, show };
}
```

### Step 3: Update Profile View

```typescript
// In Profile.vue
import { useToast } from '@/composables/useToast';

const { show: showToast } = useToast();

async function saveProfile() {
  await profileStore.updateProfile({ name: name.value });
  showToast('Profile updated successfully', 'success');
}

async function changePassword() {
  await profileStore.changePassword(currentPassword.value, newPassword.value);
  showToast('Password changed successfully', 'success');
}
```

## Acceptance Criteria

1. Success toast appears after profile update
2. Success toast appears after password change
3. Toast has `data-testid="success-toast"`
4. Toast auto-dismisses after 3 seconds
5. All 11 E2E tests pass

## Test Commands

```bash
cd vbwd-frontend && make test-e2e
```

## Related

- Sprint 14: Profile API 500 Error Fix (completed)
- E2E Tests: `profile.spec.ts`
