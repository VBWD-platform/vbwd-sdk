# Sprint 04 — Subscription Plugin Extraction

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Extract subscriptions, tarif plans, and add-ons from the core into a `subscription` plugin. Core retains only: invoicing, token economy, recurring payments, event system. The subscription plugin handles plans, subscriptions, add-ons, checkout, and its own line item processing.

---

## Motivation

- Booking-only installs carry dead subscription code
- Core hardcodes `SUBSCRIPTION`, `ADD_ON` line item handling in `PaymentCapturedHandler`, `RefundService`, `RestoreService`
- Violates: **core is agnostic — only plugins are gnostic**
- Project not yet released — best window for this refactor

---

## Architecture — Before / After

### Before (core is gnostic)

```
vbwd/ (core)
├── models/       subscription, tarif_plan, addon, addon_subscription, tarif_plan_category
├── services/     subscription_service, tarif_plan_service, tarif_plan_category_service
├── repositories/ subscription_repo, tarif_plan_repo, addon_repo, addon_sub_repo, category_repo
├── routes/       subscriptions, tarif_plans, addons + admin/subscriptions, admin/plans, admin/addons
├── handlers/     checkout_handler, subscription_handlers, subscription_cancel_handler, payment_handler (hardcoded)
├── events/       subscription_events, checkout_events
├── scheduler.py  subscription expiration, trial expiry, dunning
└── container.py  subscription DI registrations
```

### After (core is agnostic)

```
vbwd/ (core) — KEEPS:
├── models/       invoice, invoice_line_item, user, user_token_balance, token_transaction
├── services/     invoice_service, token_service, refund_service (delegates), restore_service (delegates)
├── handlers/     payment_handler (delegates to registry)
├── events/       line_item_registry (NEW), bus, domain, payment_events
├── scheduler.py  (no subscription jobs)
└── container.py  (no subscription DI)

plugins/subscription/ — NEW PLUGIN:
├── __init__.py                   SubscriptionPlugin(BasePlugin)
├── subscription/models/          subscription, tarif_plan, addon, addon_subscription, category
├── subscription/repositories/    all 5 repos
├── subscription/services/        subscription_service, tarif_plan_service, category_service, checkout_service
├── subscription/routes.py        user + admin routes (blueprint)
├── subscription/handlers/        line_item_handler, checkout_handler, subscription_handlers, cancel_handler
├── subscription/events.py        subscription_events, checkout_events
├── subscription/scheduler.py     expiration, trial, dunning jobs
├── admin-config.json
├── populate_db.py
└── tests/                        unit + integration
```

---

## Core Line Item Types After Extraction

| LineItemType | Handled by | Stays in core? |
|-------------|-----------|----------------|
| `TOKEN_BUNDLE` | Core (`CoreLineItemHandler`) | Yes — token economy is core |
| `SUBSCRIPTION` | Subscription plugin (`SubscriptionLineItemHandler`) | No |
| `ADD_ON` | Subscription plugin (`SubscriptionLineItemHandler`) | No |
| `CUSTOM` | Plugin-specific (booking, ecommerce) | Framework only |

---

## Inventory — Files Moving Out of Core

### Backend (42 files, ~10,500 lines)

| Category | Files | Lines |
|----------|-------|-------|
| Models | subscription.py, tarif_plan.py, addon.py, addon_subscription.py, tarif_plan_category.py | 583 |
| Repositories | subscription_repo, tarif_plan_repo, addon_repo, addon_sub_repo, category_repo | 490 |
| Services | subscription_service, tarif_plan_service, tarif_plan_category_service | 876 |
| Routes (user) | subscriptions.py, tarif_plans.py, addons.py | 691 |
| Routes (admin) | admin/subscriptions.py, admin/plans.py, admin/addons.py | 1,252 |
| Handlers | checkout_handler, subscription_handlers, subscription_cancel_handler | 621 |
| Events | subscription_events.py, checkout_events.py | 210 |
| Tests | 15 test files | 5,168 |
| Email templates | subscription_activated.html/txt, subscription_cancelled.html/txt | ~100 |
| Migrations | 7 alembic migration files | ~300 |

### Frontend — fe-admin (moving to subscription-admin plugin)

| File | Purpose |
|------|---------|
| `vue/src/views/Plans.vue` | Plan list with search, filter, bulk actions |
| `vue/src/views/PlanForm.vue` | Create/edit plan form |
| `vue/src/views/AddOns.vue` | Add-on list |
| `vue/src/views/AddonForm.vue` | Create/edit add-on |
| `vue/src/views/Subscriptions.vue` | Subscription list |
| `vue/src/views/SubscriptionDetails.vue` | Subscription detail |
| `vue/src/views/SubscriptionCreate.vue` | Create subscription |
| `vue/src/views/CategoryForm.vue` | Plan category form |
| `vue/src/components/CategoriesTab.vue` | Categories tab component |
| `vue/src/stores/planAdmin.ts` | Plan admin store |
| `vue/src/stores/subscriptions.ts` | Subscription admin store |
| `vue/src/stores/addons.ts` | Add-on admin store |
| `vue/src/stores/categoryAdmin.ts` | Category admin store |
| Router routes: `/admin/plans/*`, `/admin/add-ons/*`, `/admin/subscriptions/*` | |
| Sidebar nav: "Subscriptions", "Plans", "Add-Ons" items | |

### Frontend — fe-user (moving to subscription-user plugin)

| File | Purpose |
|------|---------|
| `vue/src/views/Plans.vue` | Browse plans |
| `vue/src/views/PlanDetailView.vue` | Plan detail by ID |
| `vue/src/views/TarifPlanDetail.vue` | Plan detail by slug |
| `vue/src/views/Subscription.vue` | Current subscriptions |
| `vue/src/views/AddOns.vue` | Browse add-ons |
| `vue/src/views/AddonDetail.vue` | Add-on detail |
| `vue/src/views/AddonInfoView.vue` | Add-on info |
| `vue/src/views/Checkout.vue` | Checkout flow |
| `vue/src/components/checkout/*` | Billing, email, payment, terms blocks |
| `vue/src/stores/plans.ts` | Plans store |
| `vue/src/stores/subscription.ts` | Subscription store |
| `vue/src/stores/checkout.ts` | Checkout store |
| Dashboard blocks: "Active Subscription", "Subscription History", "Add-Ons" | |
| Router routes: `/dashboard/plans/*`, `/dashboard/subscription/*`, `/dashboard/checkout/*`, `/dashboard/add-ons/*` | |
| Sidebar nav: "Plans", "Add-Ons", "Subscription", items under Store + Subscription groups | |

### Core Dashboard After (fe-user)

| Block | Status |
|-------|--------|
| Profile card | Stays in core |
| Token activity | Stays in core |
| Recent invoices | Stays in core |
| Active subscription | Moves to subscription plugin (dashboard extension) |
| Subscription history | Moves to subscription plugin (dashboard extension) |
| Add-ons | Moves to subscription plugin (dashboard extension) |
| Quick actions | **Removed from core** |

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 04a | [Line Item Handler Registry](04a-line-item-handler-registry.md) | Core: `ILineItemHandler` + `LineItemHandlerRegistry` + `CoreLineItemHandler` (token bundles only) |
| 04b | [Subscription Backend Plugin](04b-subscription-be.md) | Backend: create `plugins/subscription/` with all models, repos, services, routes, handlers, events, scheduler |
| 04c | [Remove Subscriptions from Core](04c-core-cleanup.md) | Backend: remove subscription code from `vbwd/`, update imports, slim down handlers/services |
| 04d | [Subscription Admin Frontend](04d-subscription-fe-admin.md) | fe-admin: create `subscription-admin` plugin, move views/stores/routes from core |
| 04e | [Subscription User Frontend](04e-subscription-fe-user.md) | fe-user: create `subscription-user` plugin, move views/stores/routes from core, dashboard extensions |
| 04f | [Plugin Compatibility Verification](04f-plugin-compatibility.md) | Verify all existing plugins pass tests after extraction |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before or alongside implementation. No step is done without passing tests. |
| **SOLID** | Single responsibility per component/service. Open/Closed for line item handlers. |
| **DI** | Dependencies injected, no module-level imports in business logic. |
| **DRY** | No duplicate logic between core and plugin. |
| **Liskov** | All ILineItemHandler implementations honour the interface contract. |
| **Clean code** | No `console.log`, no `as any`, no bare `except:`. Meaningful variable and method names. |
| **No over-engineering** | Minimum complexity for current task. |
| **Drop deprecated** | Remove dead code completely, no backward-compat shims. |

---

## Pre-commit Checks

Run after every step before marking it done.

### vbwd-backend
```bash
./bin/pre-commit-check.sh --lint
./bin/pre-commit-check.sh --unit
./bin/pre-commit-check.sh --integration
```

### fe-user / fe-admin
```bash
./bin/pre-commit-check.sh --style
./bin/pre-commit-check.sh --unit
./bin/pre-commit-check.sh --all
```
