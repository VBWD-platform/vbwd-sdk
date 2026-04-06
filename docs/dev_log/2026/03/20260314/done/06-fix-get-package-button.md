# Sprint 06 — Fix "Get Package" Button
**Status:** ⏳ Pending approval
**Date:** 2026-03-14

---

## Problem

When a user (logged in or anonymous) clicks **Get Package** on a software detail page (e.g. `/category/backend/loopai-core`), they are forwarded to `/checkout?tarif_plan_id=<ghrm_package_uuid>`.

Two bugs:

### Bug 1 — Wrong ID passed to checkout

`GhrmPackageDetail.vue` CTA:
```vue
:to="`/checkout?tarif_plan_id=${pkg.id}`"
```

`pkg.id` is the GHRM software package UUID (`ghrm_software_package.id`), **not** the tariff plan ID. The checkout page receives an ID it cannot resolve → broken or wrong plan loaded.

The backend already returns `tariff_plan_id` in `to_dict()` and the frontend type `GhrmPackage` simply lacks the field. Fix: add `tariff_plan_id` to the type and use `pkg.tariff_plan_id` in the CTA.

### Bug 2 — Checkout shows only one plan item with no context

Even when the correct `tariff_plan_id` is passed, the checkout (`PublicCheckoutView`) loads and displays only that single plan. For a software package the user should see:

- What they are buying (the software package name + description)
- Which plan grants access (plan name, price, billing period)
- A clear path for anonymous users: login / register → back to package → checkout

Currently: anonymous users land on a raw checkout form with one pre-selected plan and no explanation of why they are there.

---

## Requirements

- TDD-first, SOLID, DRY, no overengineering
- Do not create deprecated patterns (project not yet released — refactor freely with approval)
- Wait for final approval before implementation

---

## Steps

| # | Where | Description |
|---|-------|-------------|
| 1 | `vbwd-fe-user` — `ghrmApi.ts` | Add `tariff_plan_id: string` to `GhrmPackage` interface |
| 2 | `vbwd-fe-user` — `GhrmPackageDetail.vue` | Fix CTA: use `pkg.tariff_plan_id` instead of `pkg.id` |
| 3 | `vbwd-fe-user` — `GhrmPackageDetail.vue` | Anonymous users: CTA should redirect to `/login?redirect=<current-path>` or `/register?redirect=<current-path>` rather than directly to checkout |
| 4 | `vbwd-fe-user` — `PublicCheckoutView.vue` | When `tarif_plan_id` query param is present and the plan is linked to a GHRM package: show the package name + description as context above the plan item ("You are subscribing to access: **LoopAI Core**") |
| 5 | `vbwd-backend` — `GET /api/v1/tarif-plans/<id>` | Verify the plan endpoint returns enough info for step 4 (package name); extend if needed |
| 6 | `vbwd-fe-user` — tests | Unit tests for the CTA routing fix; E2E test for the full anonymous → login → checkout flow |

---

## Acceptance Criteria

- Clicking **Get Package** as an anonymous user redirects to `/login?redirect=/category/backend/<slug>` (returns to the package page after login)
- Clicking **Get Package** as a logged-in, non-subscribed user navigates to `/checkout?tarif_plan_id=<correct_tariff_plan_uuid>`
- The checkout page, when pre-loaded with a plan linked to a GHRM package, shows a context banner: "Access: **<package name>**"
- Clicking **Get Package** as an already-subscribed user shows "You already have access" (current behaviour is correct if `isSubscribed` hides the button — verify)
- All existing checkout unit + E2E tests continue to pass

---

## Notes

- The `tariff_plan_id` is already in the backend `to_dict()` response — this is purely a frontend fix
- The anonymous-user redirect pattern must use the same `?redirect=` query param convention already used by the auth plugin
- Step 4 (context banner) should not modify the checkout flow — it is display-only, driven by the existing `tarif_plan_id` query param
