# Sprint 06f — Shipping Plugins

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create two reference shipping plugins (flat-rate + weight-based) following the `IShippingProvider` pattern. Each has backend + fe-admin config.

## Plugins

### 1. Flat Rate Shipping (`plugins/shipping-flat-rate/`)

```
plugins/shipping-flat-rate/
├── __init__.py                    FlatRateShippingPlugin(BasePlugin)
├── shipping_flat_rate/
│   └── provider.py                FlatRateShippingProvider(IShippingProvider)
├── config.json                    See parent sprint for full config
├── admin-config.json              See parent sprint for full config
├── populate_db.py
└── tests/unit/test_provider.py
```

### 2. Weight-Based Shipping (`plugins/shipping-weight/`)

```
plugins/shipping-weight/
├── __init__.py                    WeightBasedShippingPlugin(BasePlugin)
├── shipping_weight/
│   └── provider.py                WeightBasedShippingProvider(IShippingProvider)
├── config.json                    See parent sprint for full config
├── admin-config.json              See parent sprint for full config
├── populate_db.py
└── tests/unit/test_provider.py
```

### Fe-admin: Shipping Methods Settings Page

The ecommerce-admin plugin provides a `ShippingMethods.vue` settings page (like `PaymentMethods.vue`). Lists all registered shipping providers, links to their config pages.

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `IShippingProvider` interface in core (if not done in 06c) | — |
| 2 | Flat rate provider: calculate_rate, config | `tests/unit/test_provider.py` |
| 3 | Weight-based provider: calculate_rate, zones, config | `tests/unit/test_provider.py` |
| 4 | Register both in `plugins/plugins.json` + `config.json` | — |
| 5 | Fe-admin: ShippingMethods.vue settings page | Unit tests |
| 6 | i18n: all 8 languages for both plugins | — |
| 7 | `pre-commit-check.sh` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Single responsibility per service/component. Open/Closed for shipping providers. |
| **Liskov** | All `IShippingProvider` and `ILineItemHandler` implementations honour contracts. |
| **DI** | Dependencies injected. Services via container, handlers via registry. |
| **DRY** | No duplicate logic. Shared patterns from booking plugin reused. |
| **Clean Code** | No `console.log`, no `as any`, no bare `except:`. Meaningful variable names. |
| **No over-engineering** | Minimum complexity. Stock blocking is a simple TTL table, not a distributed lock. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. CI-ready from day one. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Flat rate:
- test_flat_rate_domestic_price
- test_flat_rate_international_price
- test_flat_rate_free_shipping_above_threshold
- test_flat_rate_no_free_shipping_below_threshold

Weight-based:
- test_weight_based_calculates_by_total_weight
- test_weight_based_domestic_zone_rate
- test_weight_based_eu_zone_multiplier
- test_weight_based_international_zone_multiplier
- test_weight_based_rejects_over_max_weight
- test_weight_based_free_shipping_above_threshold

Provider registry:
- test_registered_providers_returned_by_api
- test_disabled_provider_not_in_available_methods
```

## Playwright E2E

```
- test_shipping_methods_visible_in_admin_settings
    → /admin/settings → "Shipping Methods" link → page shows providers
- test_flat_rate_config_editable
    → flat rate config page → change domestic rate → save → verify
- test_checkout_shows_shipping_options
    → checkout → shipping method step → see flat rate and weight-based options with prices
- test_checkout_shipping_selection_updates_total
    → select "Express" → total increases → select "Standard" → total decreases
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
# Backend (shipping providers)
cd vbwd-backend && ./bin/pre-commit-check.sh --full

# Admin (shipping settings page)
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
