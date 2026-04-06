# Sprint 12f — Update All Plugins to Support Access Management

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Every plugin (backend + fe-admin) fully supports access management: declares permissions, uses `@require_permission`, fe-admin routes/nav have `requiredPermission`, config settings protected by `configure` permission.

---

## Plugins to Update

### Backend: Permission Declaration + Route Migration

| Plugin | Permissions to declare | Admin routes to migrate |
|--------|----------------------|------------------------|
| **shop** | `shop.products.view/manage`, `shop.orders.view/manage`, `shop.stock.manage`, `shop.categories.manage`, `shop.warehouses.manage`, `shop.configure` | 20+ routes in `routes.py` |
| **booking** | `booking.resources.view/manage`, `booking.bookings.view/manage`, `booking.schemas.manage`, `booking.configure` | 15+ routes |
| **subscription** | `subscription.plans.view/manage`, `subscription.subscriptions.view/manage`, `subscription.addons.manage`, `subscription.configure` | 10+ routes |
| **cms** | `cms.pages.view/manage`, `cms.images.view/manage`, `cms.widgets.view/manage`, `cms.layouts.manage`, `cms.styles.manage`, `cms.configure` | 20+ routes |
| **discount** | `discount.discounts.view/manage`, `discount.coupons.view/manage`, `discount.configure` | 12 routes |
| **email** | `email.templates.view/manage`, `email.configure` | 5+ routes |
| **ghrm** | `ghrm.packages.view/manage`, `ghrm.access.view/manage`, `ghrm.configure` | 10+ routes |
| **analytics** | `analytics.view`, `analytics.configure` | 3+ routes |
| **taro** | `taro.sessions.view`, `taro.arcana.manage`, `taro.configure` | 5+ routes |
| **stripe/paypal/yookassa** | `payments.configure` | 2-3 routes each |

### Fe-Admin: Route Meta + Nav Permissions

| Plugin | Routes to add `requiredPermission` | Nav items to add `requiredPermission` |
|--------|-----------------------------------|--------------------------------------|
| **shop-admin** | 8 routes | 1 parent + 5 children |
| **booking-admin** | 6 routes | 1 parent + 4 children |
| **subscription-admin** | 5 routes | 1 parent + 3 children |
| **cms-admin** | 10 routes | 1 parent + 5 children |
| **discount-admin** | 4 routes (if created) | 1 parent + 2 children |
| **email-admin** | 3 routes | 1 parent + 1 child |
| **ghrm-admin** | 4 routes | 1 parent + 2 children |

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Shop: backend permissions + route migration | Integration tests |
| 2 | Shop: fe-admin route meta + nav permissions | Unit tests |
| 3 | Booking: backend + fe-admin | Tests |
| 4 | CMS: backend + fe-admin | Tests |
| 5 | Subscription: backend + fe-admin | Tests |
| 6 | Discount: backend + fe-admin | Tests |
| 7 | Email: backend + fe-admin | Tests |
| 8 | GHRM: backend + fe-admin | Tests |
| 9 | Analytics: backend | Tests |
| 10 | Taro: backend | Tests |
| 11 | Payment plugins (stripe/paypal/yookassa): backend | Tests |
| 12 | Core admin routes (users, invoices, settings): backend | Tests |
| 13 | Verify: super-admin can access everything | E2E test |
| 14 | Verify: limited role sees only permitted items | E2E test |
| 15 | `pre-commit-check.sh --full` all repos | — |

---

## Plugin Config Protection

Each plugin's config settings page (`/admin/settings/plugins/:pluginName`) is protected by `{plugin}.configure` permission. The settings page checks this before rendering.

```typescript
// In plugin's admin index.ts
sdk.addRoute({
  path: 'settings/plugins/shop',
  component: () => import('./PluginConfig.vue'),
  meta: { requiredPermission: 'shop.configure' },
});
```

For dangerous system settings (payment providers, API keys):
```typescript
meta: { requiredPermission: 'settings.system' }
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
