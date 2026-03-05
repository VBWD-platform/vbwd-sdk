# Sprint 04 — User E2E Test Fixes

**Priority:** MEDIUM
**Carried from:** 2026-01-23

## Remaining E2E Failures (5 tests)

1. **Profile data-testids** (2 tests) — Add `data-testid="profile-name"` and `data-testid="name-input"` to Profile.vue
2. **Usage statistics UI** (1 test) — Add usage display with `data-testid="usage-api"` to Subscription.vue
3. **Invoice modal** (1 test) — Add `data-testid="invoice-modal"` to invoice modal component
4. **Invoice payment page** (1 test) — Show "Pay Now" / "Paid" notice based on invoice status

See `reports/user-e2e-fixes.md` for full analysis.

## Acceptance Criteria
- [ ] All 5 previously failing tests pass
- [ ] No regressions in other user E2E tests
- [ ] Pre-commit checks pass
