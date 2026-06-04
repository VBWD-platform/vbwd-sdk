# Sprint 12c — Backend: Plugin Permission Declaration

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Add `admin_permissions` property to `BasePlugin`. Each plugin declares its permissions. Migrate all admin routes from `@require_admin` to `@require_permission()`.

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Add `admin_permissions` property to `BasePlugin` (default: empty list) | Interface test |
| 2 | Add `admin_permissions` to `ShopPlugin` | Plugin test |
| 3 | Add `admin_permissions` to `BookingPlugin` | Plugin test |
| 4 | Add `admin_permissions` to `SubscriptionPlugin` | Plugin test |
| 5 | Add `admin_permissions` to `CmsPlugin` | Plugin test |
| 6 | Add `admin_permissions` to `DiscountPlugin` | Plugin test |
| 7 | Add `admin_permissions` to `EmailPlugin` | Plugin test |
| 8 | Add `admin_permissions` to `GhrmPlugin` | Plugin test |
| 9 | Add `admin_permissions` to `AnalyticsPlugin` | Plugin test |
| 10 | Add `admin_permissions` to `TaroPlugin` | Plugin test |
| 11 | Migrate shop routes: `@require_admin` → `@require_permission('shop.*')` | Integration tests |
| 12 | Migrate booking routes | Integration tests |
| 13 | Migrate CMS routes | Integration tests |
| 14 | Migrate subscription routes | Integration tests |
| 15 | Migrate core admin routes (users, invoices, settings) | Integration tests |
| 16 | Migrate all remaining plugin admin routes | Integration tests |
| 17 | Auto-register plugin permissions in DB on plugin enable | Registration test |
| 18 | `pre-commit-check.sh --full` | — |

---

## Plugin Permission Declaration Pattern

```python
class ShopPlugin(BasePlugin):
    @property
    def admin_permissions(self) -> list[dict]:
        return [
            {"key": "shop.products.view", "label": "View products", "group": "Shop"},
            {"key": "shop.products.manage", "label": "Manage products", "group": "Shop"},
            {"key": "shop.orders.view", "label": "View orders", "group": "Shop"},
            {"key": "shop.orders.manage", "label": "Manage orders", "group": "Shop"},
            {"key": "shop.stock.manage", "label": "Manage stock", "group": "Shop"},
            {"key": "shop.categories.manage", "label": "Manage categories", "group": "Shop"},
            {"key": "shop.warehouses.manage", "label": "Manage warehouses", "group": "Shop"},
            {"key": "shop.configure", "label": "Shop settings", "group": "Shop"},
        ]
```

## Route Migration Pattern

```python
# Before:
@require_auth
@require_admin
def admin_list_products():

# After:
@require_auth
@require_permission("shop.products.view")
def admin_list_products():
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
