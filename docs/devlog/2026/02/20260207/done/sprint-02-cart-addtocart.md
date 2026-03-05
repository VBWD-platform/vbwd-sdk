# Sprint 02 — AddToCart Buttons Not Working

**Priority:** HIGH
**Carried from:** 2026-01-30 (cart store reactivity issue)

## Problem

On the AddOns and Tokens pages, clicking "Add to Cart" does nothing. The cart store from `@vbwd/view-component` loses reactivity when imported into the user app due to Pinia instance mismatch.

## Root Cause

Pinia store instance created in `@vbwd/view-component` is a different instance than the one the user app's Pinia recognizes. Values copied to local `ref()` variables lose reactivity link to the store.

See `reports/cart-store-fix.md` for full analysis and proposed solutions.

## Files to Modify
- `vbwd-frontend/user/vue/src/views/AddOns.vue`
- `vbwd-frontend/user/vue/src/views/Tokens.vue`
- `vbwd-frontend/user/vue/src/views/Plans.vue`
- `vbwd-frontend/user/vue/src/views/Checkout.vue`
- `vbwd-frontend/core/src/stores/cart.ts` (if re-export approach needed)

## Acceptance Criteria
- [ ] AddToCart works on AddOns page
- [ ] AddToCart works on Tokens page
- [ ] Cart badge updates with item count
- [ ] Cart persists across page navigation
- [ ] Pre-commit checks pass
