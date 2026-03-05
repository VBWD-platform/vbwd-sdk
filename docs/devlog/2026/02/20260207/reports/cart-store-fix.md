# Cart Store Reactivity Fix

**Priority:** HIGH
**Carried from:** 2026-01-30 (sprint-03, sprint-04, sprint-05)
**Blocking:** 14 E2E tests in plans/tokens/addons pages

## Problem

When importing `useCartStore` from `@vbwd/view-component`, the Pinia store loses reactivity in the user app. Cart items added via store actions don't reflect in the UI.

### Current State
- Cart store implemented in `vbwd-frontend/core/src/stores/cart.ts` with 26 unit tests passing
- Pages created: `/tokens` (6/7 tests), `/add-ons` (9/10 tests)
- Total: 15/29 E2E tests passing, 14 failing due to cart reactivity

### Root Cause
Pinia store instance created in `@vbwd/view-component` is a different instance than the one the user app's Pinia recognizes. Values copied to local `ref()` variables lose reactivity link to the store.

## Proposed Solution (from sprint-05)

**Option A: Direct store reference (Recommended)**
- Use store directly in templates instead of copying to local refs
- Use `shallowRef` for store reference
- Add optional chaining for null safety
- Remove intermediate ref copies

### Files to Modify
- `vbwd-frontend/user/vue/src/views/Plans.vue`
- `vbwd-frontend/user/vue/src/views/Tokens.vue`
- `vbwd-frontend/user/vue/src/views/AddOns.vue`
- `vbwd-frontend/user/vue/src/views/Checkout.vue`

### Alternative Approaches (if Option A fails)
1. Lazy-load cart store with Pinia availability check
2. Re-export cart store from user app instead of importing from core
3. Use `storeToRefs()` for reactive destructuring
4. Move cart store definition to user app, keep interface in core

## Acceptance Criteria
- [ ] 29/29 E2E tests passing for plans, tokens, add-ons pages
- [ ] Cart persists across page navigation (localStorage)
- [ ] Cart badge shows correct item count
- [ ] Add/remove items updates UI immediately
- [ ] Pre-commit checks pass
