# Sprint 04f — Plugin Compatibility Verification

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Verify all existing plugins still work after the subscription extraction. Fix any breakages. All tests must be green.

---

## Condition

**cms, landing1, booking plugins MUST be working with all tests green when this sprint completes.**

---

## Impact Analysis per Plugin

### Backend Plugins

| Plugin | Imports from subscription code? | Risk | Action |
|--------|---------------------------------|------|--------|
| **booking** | No direct imports. Uses `LineItemType.CUSTOM`. `BookingLineItemHandler` registered via registry. | Low | Verify line item handler works. Already refactored in 04a. |
| **analytics** | No subscription imports. | None | Smoke test only. |
| **chat** | No subscription imports. | None | Smoke test only. |
| **cms** | No subscription imports. | None | Verify tests green. |
| **email** | Listens to `invoice.paid`, `subscription.activated`, `booking.created` events. | Medium | `subscription.activated` now published by subscription plugin, not core. Verify event still fires. |
| **ghrm** | No subscription imports. | None | Smoke test only. |
| **mailchimp** | No subscription imports. | None | Smoke test only. |
| **stripe** | Calls `emit_payment_captured()` (core). `_reconcile_payment()` (core). | Low | Core payment helpers unchanged. Verify webhook → subscription activation flow works end-to-end. |
| **paypal** | Same as stripe — uses `emit_payment_captured()`. | Low | Same verification. |
| **yookassa** | Same as stripe — uses `emit_payment_captured()`. | Low | Same verification. |
| **taro** | Uses token balance (core). No subscription imports. | None | Smoke test only. |

### Frontend Plugins — fe-user

| Plugin | References subscription/plan/addon? | Risk | Action |
|--------|-------------------------------------|------|--------|
| **landing1** | Links to `/dashboard/plans`. | Medium | Update links to go through subscription plugin route (only if plugin installed). |
| **booking** | Own checkout flow (booking-specific). No plan references. | Low | Verify booking checkout + invoice flow works. |
| **checkout** | **Subscription-specific.** Links to plans, displays subscription status. | High | Merged into subscription plugin in 04e. Delete `plugins/checkout/`. |
| **cms** | No subscription references. | None | Verify tests green. |
| **ghrm** | No subscription references. | None | Smoke test only. |
| **taro** | Uses tokens (core). No subscription references. | None | Smoke test only. |
| **chat** | No subscription references. | None | Smoke test only. |
| **theme-switcher** | UI only. | None | Smoke test only. |
| **stripe-payment** | Payment method registration. No plan references. | Low | Verify payment flow works. |
| **paypal-payment** | Same as stripe. | Low | Same verification. |
| **yookassa-payment** | Same as stripe. | Low | Same verification. |

### Frontend Plugins — fe-admin

| Plugin | References subscription/plan? | Risk | Action |
|--------|-------------------------------|------|--------|
| **analytics-widget** | Dashboard widget. No subscription references. | None | Smoke test only. |
| **taro-admin** | No subscription references. | None | Smoke test only. |
| **cms-admin** | No subscription references. | None | Verify tests green. |
| **ghrm-admin** | No subscription references. | None | Smoke test only. |
| **email-admin** | Lists email templates. May reference `subscription.activated` event type. | Low | Event type is a string — still works. |
| **booking** | No subscription references. Own admin views. | Low | Verify tests green. |

---

## Steps

| # | What | Validate |
|---|------|----------|
| 1 | Run full backend test suite: `make test` + `make test-integration` | All green |
| 2 | Run booking plugin tests: `pytest plugins/booking/tests/ -v` | All green |
| 3 | Run subscription plugin tests: `pytest plugins/subscription/tests/ -v` | All green |
| 4 | Run cms plugin tests: `pytest plugins/cms/tests/ -v` | All green |
| 5 | Run email plugin tests: `pytest plugins/email/tests/ -v` | All green |
| 6 | Run stripe plugin tests: `pytest plugins/stripe/tests/ -v` | All green |
| 7 | Verify end-to-end: Stripe payment → subscription activation → email sent | Manual or integration test |
| 8 | Verify end-to-end: Booking payment → booking created → email sent | Manual or integration test |
| 9 | Fix `landing1` links if they reference removed core routes | — |
| 10 | Delete `plugins/checkout/` from fe-user (merged into subscription plugin) | — |
| 11 | Update `plugins/plugins.json` in fe-user — remove `checkout` entry | — |
| 12 | Run fe-admin tests: `npm run test` | All green |
| 13 | Run fe-user tests: `npm run test` | All green |
| 14 | Run all CI pipelines or `pre-commit-check.sh` on all repos | All green |

---

## Fixes Expected

1. **email plugin**: May need to import `subscription.activated` event type string from subscription plugin's events module (or keep as string literal — already works).
2. **landing1 plugin**: Links to `/dashboard/plans` — must handle gracefully if subscription plugin not installed (route won't exist). Add guard or make link conditional.
3. **checkout plugin** (fe-user): Delete entirely — merged into subscription-user plugin.
4. **Invoice model**: `subscription_id` / `tarif_plan_id` columns now nullable FKs. Existing data intact. Admin invoice views may show "N/A" for subscription details — acceptable.

---

## Acceptance Criteria

- `make pre-commit` green on vbwd-backend
- `pre-commit-check.sh` green on fe-admin and fe-user
- All plugin-specific tests green: booking, cms, email, stripe, subscription
- Booking end-to-end works: checkout → payment → booking created → admin list shows booking
- Subscription end-to-end works: checkout → payment → subscription active → email sent
- No broken imports in any plugin
- `landing1` handles missing subscription plugin gracefully
