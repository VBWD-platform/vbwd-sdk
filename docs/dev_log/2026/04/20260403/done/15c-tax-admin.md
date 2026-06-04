# Sprint 15c — Tax Configuration (Core)

**Status:** Done
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [15 — Shipping & Discount Admin](15-shipping-discount-admin.md)

---

## Goal

Full tax CRUD in core admin settings — tax rates per country/region, tax classes, tax calculation rules. Agnostic — applies to any invoice line item regardless of plugin.

---

## Architecture

### Models (already exist in core)

- `vbwd_tax` — tax definition (name, rate, type, country, region)
- `vbwd_tax_rate` — specific rate per country/region combination

### Backend Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/admin/tax/rates` | List tax rates (with filters) |
| POST | `/admin/tax/rates` | Create tax rate |
| GET | `/admin/tax/rates/<id>` | Tax rate detail |
| PUT | `/admin/tax/rates/<id>` | Update tax rate |
| DELETE | `/admin/tax/rates/<id>` | Delete tax rate |
| GET | `/admin/tax/classes` | List tax classes (standard, reduced, zero) |
| POST | `/admin/tax/classes` | Create tax class |
| PUT | `/admin/tax/classes/<id>` | Update tax class |
| DELETE | `/admin/tax/classes/<id>` | Delete tax class |

### Fe-Admin (core Settings)

- Settings → "Tax" tab (alongside existing tabs)
- Tax Rates table: country, region, rate %, tax class, status
- Tax Classes list: name, description, default rate
- Country picker uses existing `vbwd_country` table

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Review existing Tax/TaxRate models, add missing fields if needed | — |
| 2 | Backend: tax admin routes (CRUD for rates + classes) | Route tests |
| 3 | Fe-admin: TaxRates list + form | Unit tests |
| 4 | Fe-admin: TaxClasses list + form | Unit tests |
| 5 | Fe-admin: Add "Tax" tab to Settings page | — |
| 6 | Permissions: `settings.manage` for tax config | — |
| 7 | i18n: all 8 languages | — |
| 8 | Playwright E2E: create tax rate, edit, delete | E2E tests |
| 9 | `pre-commit-check.sh --full` | — |

---

## Playwright E2E

```
- test_admin_create_tax_rate
    → Settings → Tax → New Rate → select country DE, rate 19%, class "standard" → save → visible in list
- test_admin_edit_tax_rate
    → click rate → change to 20% → save → updated in list
- test_admin_delete_tax_rate
    → select rate → delete → removed from list
- test_admin_create_tax_class
    → New Class → "Luxury" → 25% → save → visible
- test_tax_rate_linked_to_country
    → rate shows country name from vbwd_country table
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
