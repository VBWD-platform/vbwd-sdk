# User App E2E Test Fixes

**Priority:** MEDIUM
**Carried from:** 2026-01-23 (sprint-01-e2e-test-analysis)
**Tests affected:** 5 failing tests

## Background

On 2026-01-23, user app E2E tests showed 86 passed / 26 failed. The 2026-01-30 session fixed the checkout tests (17 failures from missing `confirm-checkout` testid + 1 auth redirect). The remaining 5 failures are still open.

## Remaining Failures

### 1. Missing Profile Data-testids (2 tests)
**File:** `vbwd-frontend/user/vue/tests/e2e/profile.spec.ts`
**Fix:** Add `data-testid="profile-name"` and `data-testid="name-input"` to Profile.vue
**Effort:** Small

### 2. Missing Usage Statistics UI (1 test)
**File:** `vbwd-frontend/user/vue/tests/e2e/subscription.spec.ts`
**Fix:** Add usage statistics display with `data-testid="usage-api"` and related elements to Subscription.vue
**Effort:** Medium — requires implementing usage display component

### 3. Missing Invoice Modal (1 test)
**File:** `vbwd-frontend/user/vue/tests/e2e/subscription-data.spec.ts`
**Fix:** Add `data-testid="invoice-modal"` to invoice modal component
**Effort:** Small

### 4. Invoice Payment Page (1 test)
**File:** `vbwd-frontend/user/vue/tests/e2e/invoices.spec.ts` (or related)
**Fix:** Payment page should show "Pay Now" button or "Paid" notice based on invoice status
**Effort:** Medium — requires checking InvoicePay.vue and InvoiceDetail.vue state handling

## Files to Modify
- `vbwd-frontend/user/vue/src/views/Profile.vue`
- `vbwd-frontend/user/vue/src/views/Subscription.vue`
- `vbwd-frontend/user/vue/src/components/InvoiceModal.vue` (may need creation)
- `vbwd-frontend/user/vue/src/views/InvoicePay.vue`

## Acceptance Criteria
- [ ] profile.spec.ts — 2 previously failing tests now pass
- [ ] subscription.spec.ts — usage statistics test passes
- [ ] subscription-data.spec.ts — invoice modal test passes
- [ ] Invoice payment page test passes
- [ ] No regressions in other user E2E tests
- [ ] Pre-commit checks pass
