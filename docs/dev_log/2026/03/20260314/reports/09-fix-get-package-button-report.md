# Sprint 06 — Fix "Get Package" Button: Completion Report

**Date:** 2026-03-15
**Status:** ✅ Done

---

## What Was Done

### Bug 1 — Wrong ID passed to checkout ✅ (already fixed in prior session)

`GhrmPackage` type in `ghrmApi.ts` already had `tariff_plan_id: string` added, and
`GhrmPackageDetail.vue` CTA already used `pkg.tariff_plan_id` with `package_name` and
`package_slug` forwarded as query params.

### Bug 2 — Context banner ✅ (already in place)

`GhrmCheckoutContext.vue` already existed and was registered via `checkoutContextRegistry`
in `plugins/ghrm/index.ts`. The banner reads `route.query.package_name` and displays
"Access: **{package_name}**" inline above the checkout plan.

### Bug 3 — Anonymous redirect (this session) ✅

**Before:** Used `sessionStorage.setItem('redirect_after_login', path)` + `router.push('/login')`

**After:** Uses `router.push({ path: '/login', query: { redirect: route.fullPath } })`

This aligns with the `?redirect=` convention used by the auth router guard.

**Login.vue** updated to read `route.query.redirect` first (query param takes priority),
then fall back to `sessionStorage.getItem('redirect_after_login')` for backward compat.

---

## Files Changed

| File | Change |
|------|--------|
| `vbwd-fe-user/plugins/ghrm/src/views/GhrmPackageDetail.vue` | Anonymous redirect → `?redirect=` query param |
| `vbwd-fe-user/vue/src/views/Login.vue` | Read `route.query.redirect` before sessionStorage |
| `vbwd-fe-user/vue/tests/unit/plugins/ghrm-get-package.spec.ts` | Update test expectations to new redirect pattern |

---

## Tests

All 4 tests in `ghrm-get-package.spec.ts` pass:

- `renders Get Package button when not subscribed` ✓
- `redirects anonymous user to /login with ?redirect= query param` ✓
- `navigates authenticated user to /checkout with correct tariff_plan_id` ✓
- `does NOT pass the GHRM package id (pkg.id) as tarif_plan_id` ✓

---

## CI Fixes (same session)

Also fixed fe-admin CI unit test failures (4 → 0):

| Fix | File |
|-----|------|
| `@plugins` vitest alias pointed to wrong dir (`../plugins` → `./plugins`) | `vbwd-fe-admin/vitest.config.js` |
| emailAdminPlugin test expected `navSections` but plugin now uses `settingsItems` | `plugins/email-admin/tests/unit/emailAdminPlugin.spec.ts` |
| AddonForm test used lowercase `'monthly'` but option values are `'MONTHLY'` | `vue/tests/unit/views/addon-form.spec.ts` |
| AddOns row click handler was on inner `<td>` instead of `<tr>` | `vue/src/views/AddOns.vue` |
