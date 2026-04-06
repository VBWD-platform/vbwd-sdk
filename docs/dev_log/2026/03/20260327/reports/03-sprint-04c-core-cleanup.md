# Report 03 — Sprint 04c: Remove Subscriptions from Core

**Date:** 2026-03-27
**Status:** Done

---

## What Was Done

Removed all subscription/tarif-plan/add-on code from `vbwd/` core. Core is now a pure invoicing + token economy + event system.

### Removed from Core

- **container.py**: Removed 6 DI registrations (subscription_repo, tarif_plan_repo, addon_repo, addon_sub_repo, category_repo, subscription_service, tarif_plan_service, category_service, refund_service subscription deps)
- **app.py**: Removed 7 blueprint registrations, checkout_handler, cancel_handler, subscription scheduler
- **scheduler.py**: Removed subscription expiration/trial/dunning jobs, kept only booking completion
- **payment_handler.py**: Removed `_publish_subscription_activated()` (now plugin's responsibility)
- **core_line_item_handler.py**: Stripped to TOKEN_BUNDLE only (290→165 lines)
- **admin routes `__init__.py`**: Removed admin_subs_bp, admin_plans_bp, admin_addons_bp, admin_categories_bp exports

### Tests Cleaned Up

- Deleted `test_scheduler.py` (subscription jobs tests)
- Deleted `test_subscription_service.py`, `test_tarif_plan_service.py`, `test_tarif_plan_category_service.py`
- Deleted `test_subscription_handlers.py`, `test_subscription_cancel_handler.py`
- Deleted `test_subscription.py`, `test_addon_tarif_plans.py`, `test_tarif_plan_category.py`
- Deleted `test_public_addon_plans.py`, `test_user_addon_detail.py`, `test_admin_addon_plans.py`, `test_admin_user_addons.py`
- Deleted integration checkout + subscription flow tests
- Updated `test_container.py` — removed subscription repo/service assertions
- Updated `test_app.py` — removed subscription_service assertion
- Updated `test_core_line_item_handler.py` — TOKEN_BUNDLE tests only

### Test Results

- **653 passed, 0 failed, 4 skipped** (down from 790 — deleted subscription tests moved to plugin)

---

## Lessons Learned

### 1. Flask endpoint name conflicts on shared blueprints

When merging 6 route files (3 user + 3 admin) onto a single blueprint, duplicate function names cause `AssertionError: View function mapping is overwriting an existing endpoint function`. Both `user_subscriptions.py` and `admin_subscriptions.py` had `list_subscriptions()`.

**Fix:** Prefixed all admin route functions with `admin_` (e.g., `admin_list_subscriptions`, `admin_list_plans`).

**Rule:** When combining multiple route modules on one blueprint, enforce unique function names — prefix with `admin_` or `user_`.

### 2. Routes with empty string path need explicit prefix

Original routes used `@bp.route("")` with `url_prefix` set at registration time. When moving to a shared blueprint without prefix, `""` is an invalid URL rule.

**Fix:** Replaced `""` with the full absolute path (e.g., `/api/v1/user/subscriptions`).

### 3. Plugin config access in `on_enable`

`self.config` is set by `initialize()` which may not be called before `on_enable()` in test contexts. Using `getattr(self, "config", {}) or {}` is defensive.

---

## Core After Cleanup

```
vbwd/ (core) — what remains:
├── models/       user, invoice, invoice_line_item, token_balance, token_transaction, enums (kept for DB compat)
├── services/     auth, user, invoice, token, refund (delegates), restore (delegates), currency, tax
├── handlers/     payment_handler (invoice.paid only), core_line_item_handler (TOKEN_BUNDLE only)
├── routes/       auth, user, invoices, token_bundles, admin/(users, invoices, profile, settings, plugins, countries, payment_methods)
├── events/       line_item_registry, bus, domain, payment_events
└── container.py  no subscription DI
```

Note: Model files (subscription.py, tarif_plan.py, etc.) still exist in `vbwd/models/` because the plugin re-exports from them. They will remain until Phase 2 when the plugin owns the model files directly.
