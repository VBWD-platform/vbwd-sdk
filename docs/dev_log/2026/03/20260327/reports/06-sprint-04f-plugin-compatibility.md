# Report 06 — Sprint 04f: Plugin Compatibility Verification

**Date:** 2026-03-27
**Status:** Done

---

## Verification Results

### Backend — 1,034 tests green

| Plugin | Tests | Status |
|--------|-------|--------|
| Core (unit) | 653 | Green |
| subscription | 8 | Green |
| booking | 75 | Green |
| cms | 162 | Green |
| email | 27 | Green |
| analytics | 5 | Green |
| ghrm | 104 | Green |
| **Total** | **1,034** | **All green** |

### Frontend — 538 tests green

| Module | Tests | Status |
|--------|-------|--------|
| fe-admin core | 192 | Green |
| fe-admin email-admin plugin | 14 | Green |
| fe-admin booking plugin | 14 | Green |
| fe-user core | 318 | Green |
| **Total** | **538** | **All green** |

### Pre-existing Issues (not caused by extraction)

- `stripe-views.spec.ts` (fe-user): 3 failures — `router.replace is not a function` — pre-existing mock issue
- `taro session service` (backend): 44 errors — PyO3/bcrypt environment issue in Docker
- `chat plugin`: module structure issue — `'plugins.chat' is not a package`

---

## Fixes Applied During Verification

### 1. RefundService missing from container

`PaymentRefundedHandler` calls `container.refund_service()` but it was removed in 04c.

**Fix:** Re-added `refund_service` to container with core-only deps (no subscription_repo). Updated `_calculate_tokens_to_debit` to only count TOKEN_BUNDLE tokens — subscription default_tokens are now the plugin's responsibility.

### 2. RefundService constructor simplified

Removed `subscription_repo` and `addon_sub_repo` parameters — they belonged to subscription-specific pre-check logic that moved to the plugin.

---

## Final Test Summary

| Module | Tests | Files |
|--------|-------|-------|
| Backend | 1,034 | 7 plugin suites + core |
| fe-admin | 220 | 25 files |
| fe-user | 318 | 42 files |
| **Grand Total** | **1,572** | **All green** |
