# Sprint 15b — Discount Admin Plugin (Core)

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [15 — Shipping & Discount Admin](15-shipping-discount-admin.md)

---

## Goal

Create `discount-admin` as a standalone fe-admin plugin. Full CRUD for discounts and coupons. Coupon auto-generator. Usage analytics.

Backend API already exists (Sprint 08a). This sprint is frontend only.

---

## Plugin Structure

```
plugins/discount-admin/
├── index.ts                    Plugin entry: routes + sidebar nav + i18n
├── config.json
├── admin-config.json
├── src/
│   ├── views/
│   │   ├── Discounts.vue       List: name, type, scope, value, uses, status
│   │   ├── DiscountForm.vue    Create/edit: type, value, scope, conditions, limits, dates
│   │   ├── Coupons.vue         List: code, linked discount, uses, status
│   │   ├── CouponForm.vue      Create/edit: code (manual/auto), discount link, limits, dates
│   │   └── CouponUsage.vue     Usage history per coupon
│   └── stores/
│       └── discountAdmin.ts    Pinia store: discounts, coupons, usage
├── locales/
│   ├── en.json ... zh.json     8 languages
└── tests/
    └── unit/
        ├── Discounts.spec.ts
        └── DiscountForm.spec.ts
```

---

## Sidebar Navigation

Injected into Sales section as "Promotions" with children:

```typescript
extensionRegistry.register('discount-admin', {
  sectionItems: {
    sales: [{
      label: 'Promotions',
      to: '/admin/promotions/discounts',
      id: 'promotions',
      requiredPermission: 'discount.discounts.view',
      children: [
        { label: 'Discounts', to: '/admin/promotions/discounts', requiredPermission: 'discount.discounts.view' },
        { label: 'Coupons', to: '/admin/promotions/coupons', requiredPermission: 'discount.coupons.view' },
      ],
    }],
  },
});
```

---

## Views

### Discounts List (`Discounts.vue`)

| Column | Content |
|--------|---------|
| Name | Link to edit form |
| Type | Badge: PERCENTAGE / FIXED_AMOUNT / FREE_SHIPPING / BUY_X_GET_Y |
| Scope | Badge: GLOBAL / ECOMMERCE / SUBSCRIPTION / BOOKING |
| Value | "20%" or "€5.00" |
| Uses | "45 / 500" (current / max) |
| Status | Active / Expired / Inactive |
| Actions | Edit, Delete |

Bulk: select + bulk delete, bulk activate/deactivate

### Discount Form (`DiscountForm.vue`)

| Field | Type |
|-------|------|
| Name | Text input |
| Slug | Auto-generated, editable |
| Discount Type | Select: PERCENTAGE, FIXED_AMOUNT, FREE_SHIPPING, BUY_X_GET_Y |
| Value | Number input (% or fixed amount) |
| Currency | Text input (for FIXED_AMOUNT) |
| Scope | Select: GLOBAL, ECOMMERCE, SUBSCRIPTION, BOOKING |
| Conditions | JSON editor (product IDs, category IDs, plan IDs) |
| Min Order Amount | Number input |
| Max Discount Amount | Number input (cap for percentage) |
| Max Uses | Number input (null = unlimited) |
| Max Uses Per User | Number input |
| Stackable | Checkbox |
| Priority | Number input (lower = higher priority) |
| Starts At | DateTime picker |
| Expires At | DateTime picker |
| Active | Checkbox |

### Coupons List (`Coupons.vue`)

| Column | Content |
|--------|---------|
| Code | Monospace, link to edit |
| Discount | Linked discount name |
| Uses | "12 / 100" |
| Status | Active / Expired / Inactive |
| Actions | Edit, Delete, View Usage |

Bulk: select + bulk delete

### Coupon Form (`CouponForm.vue`)

| Field | Type |
|-------|------|
| Code | Text input (uppercase) OR auto-generate button |
| Discount | Select dropdown (from available discounts) |
| Max Uses | Number input |
| Max Uses Per User | Number input |
| Starts At | DateTime picker |
| Expires At | DateTime picker |
| Active | Checkbox |

**Auto-generate:**
- "Generate Code" button → creates random 8-char alphanumeric uppercase code
- "Bulk Generate" button → input count (N) → creates N coupon records with random codes linked to selected discount

### Coupon Usage (`CouponUsage.vue`)

Table: user email, invoice number, discount amount, used at

---

## API Endpoints (already exist)

| Method | Path | View |
|--------|------|------|
| GET | `/admin/discounts` | Discounts list |
| POST | `/admin/discounts` | Create discount |
| GET | `/admin/discounts/<id>` | Discount detail |
| PUT | `/admin/discounts/<id>` | Update discount |
| DELETE | `/admin/discounts/<id>` | Delete discount |
| GET | `/admin/coupons` | Coupons list |
| POST | `/admin/coupons` | Create coupon |
| GET | `/admin/coupons/<id>` | Coupon detail |
| PUT | `/admin/coupons/<id>` | Update coupon |
| DELETE | `/admin/coupons/<id>` | Delete coupon |
| GET | `/admin/coupons/<id>/usage` | Usage history |

**New endpoint needed:**
| POST | `/admin/coupons/generate` | Bulk generate coupons |

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create plugin skeleton: `index.ts`, locales, config | — |
| 2 | `discountAdmin.ts` store — CRUD actions | Unit tests |
| 3 | `Discounts.vue` — list with filters, bulk actions | Unit tests |
| 4 | `DiscountForm.vue` — create/edit with type-dependent fields | Unit tests |
| 5 | `Coupons.vue` — list with status badges | Unit tests |
| 6 | `CouponForm.vue` — code input + auto-generate + discount link | Unit tests |
| 7 | `CouponUsage.vue` — usage history table | Unit tests |
| 8 | Backend: `POST /admin/coupons/generate` route | Route tests |
| 9 | Sidebar: "Promotions" in Sales section | — |
| 10 | i18n: all 8 languages | — |
| 11 | `requiredPermission` on all routes + nav | — |
| 12 | Playwright E2E: discount CRUD, coupon CRUD, auto-generate, usage | E2E tests |
| 13 | `pre-commit-check.sh --full` | — |

---

## Playwright E2E

```
- test_create_percentage_discount
    → Promotions → Discounts → New → 20% GLOBAL → save → in list
- test_create_fixed_discount_with_min_order
    → New → FIXED_AMOUNT €5, min order €25 → save
- test_edit_discount_value
    → click → change value → save → updated
- test_delete_discount
    → select → delete → removed
- test_create_coupon_manual_code
    → Coupons → New → code "WELCOME10" → link discount → save
- test_auto_generate_coupon_code
    → New → Generate Code → random code appears → save
- test_bulk_generate_5_coupons
    → Bulk Generate → select discount → count 5 → generate → 5 new in list
- test_coupon_usage_shows_redemptions
    → Coupon detail → Usage tab → records visible
- test_promotions_sidebar_visible
    → login → sidebar has "Promotions" with "Discounts" + "Coupons" children
- test_promotions_hidden_without_permission
    → login as user without discount.discounts.view → "Promotions" not in sidebar
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
