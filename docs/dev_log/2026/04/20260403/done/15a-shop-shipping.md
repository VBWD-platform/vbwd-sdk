# Sprint 15a — Shop: Shipping Methods

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [15 — Shipping & Discount Admin](15-shipping-discount-admin.md)

---

## Goal

Shipping method management in the shop-admin plugin. Built-in "pick-up at store" method. Shipping provider plugins register themselves and subscribe to order events.

---

## Architecture

```
Shop Plugin (owns shipping feature)
├── Built-in method: "Pick-up at Store" (no cost, no tracking)
├── ShippingMethodRegistry — providers register here
└── Admin UI: list methods, enable/disable, configure events

Shipping Provider Plugins (depend on shop)
├── shipping-flat-rate → config.json/admin-config.json for rates
├── shipping-weight-based → config.json/admin-config.json for weight rules
└── Each subscribes to: order.created, order.shipped (configurable by admin)
```

### Backend

- `ShippingMethodRegistry` in shop plugin — providers register on enable
- `GET /admin/shop/shipping/methods` — list all registered methods (built-in + plugins)
- `PUT /admin/shop/shipping/methods/<id>/toggle` — enable/disable a method
- `GET /admin/shop/shipping/methods/<id>/events` — list subscribed events
- `PUT /admin/shop/shipping/methods/<id>/events` — configure event subscriptions
- Built-in "pick-up at store" always available, configurable (address, hours)

### Fe-Admin (shop-admin plugin)

- `ShippingMethods.vue` — list page: name, type (built-in/plugin), status, rate summary
- Shipping provider config → links to `/admin/settings/backend-plugins/{provider}` (existing plugin config page)
- Sidebar: "Shop" → "Shipping" child item
- Route: `shop/shipping` with `requiredPermission: 'shop.configure'`

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `ShippingMethodRegistry` in shop plugin backend | Unit tests |
| 2 | Built-in "pick-up at store" method | Unit tests |
| 3 | Shipping admin routes (list, toggle, events) | Route tests |
| 4 | Update `shipping-flat-rate` plugin to register with shop | Integration test |
| 5 | `ShippingMethods.vue` — list + toggle + event config | Unit tests |
| 6 | Add "Shipping" to shop-admin sidebar | — |
| 7 | i18n: all 8 languages | — |
| 8 | `pre-commit-check.sh --full` | — |

---

## Playwright E2E

```
- test_shipping_methods_page_shows_providers
    → login → Shop → Shipping → "Pick-up at Store" visible + any registered providers
- test_toggle_shipping_method_on_off
    → disable method → badge changes → re-enable → active
- test_shipping_config_link_opens_plugin_settings
    → click provider → navigates to /admin/settings/backend-plugins/{name}
- test_pickup_at_store_always_available
    → built-in method cannot be deleted, always in list
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
