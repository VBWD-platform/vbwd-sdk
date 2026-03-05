# Sprint 15 Report — Settings Payments Tab Cleanup

**Date:** 2026-02-09
**Status:** DONE
**Priority:** MEDIUM

---

## Summary

Two fixes:
1. **Backend bug:** `settings.py` had a hardcoded mock `/admin/payment-methods` endpoint returning fake "Bank Transfer" and "Credit Card" data. Since `admin_settings_bp` was registered before `admin_payment_methods_bp` in Flask, the mock route shadowed the real DB-backed endpoint. Removed the mock.
2. **Frontend cleanup:** Removed the redundant "Payments" tab from the admin Settings page. Payment methods are already fully managed via the standalone `/admin/payment-methods` page.

---

## Problem

1. **Backend route conflict:** `src/routes/admin/settings.py` contained a mock `GET /api/v1/admin/payment-methods` endpoint with hardcoded data (`[{id: "1", name: "Bank Transfer"}, {id: "2", name: "Credit Card"}]`). Because `admin_settings_bp` was registered before `admin_payment_methods_bp` in `app.py`, Flask matched the mock route first — the real endpoint in `payment_methods.py` (which queries the `payment_method` DB table) was never reached.
2. **Settings.vue** had a "Payments" tab containing a read-only list of payment methods — redundant with the standalone `/admin/payment-methods` page that provides full CRUD.

## Database State

The `payment_method` table contains 1 entry (seeded by migration):
- **Invoice** — code: `invoice`, position: 0, fee_type: `none`, active, default

---

## Changes

### Backend

| File | Change |
|------|--------|
| `src/routes/admin/settings.py` | Removed mock `_payment_methods` list and `get_payment_methods()` route that was shadowing the real endpoint in `payment_methods.py` |

### Frontend — Admin

| File | Change |
|------|--------|
| `src/views/Settings.vue` | Removed Payments tab button, tab content (subtabs + payment methods list + Tab2 placeholder), `PaymentMethod` interface, `paymentMethods` ref, `paymentsSubtab` state, `PaymentsSubtab` type, payment methods fetch from `fetchSettings()`, and related CSS |
| `tests/integration/Settings.spec.ts` | Removed `tab-payments` assertion from tab rendering test, removed payments tab from tab-switching test, removed "displays payments subtabs" test entirely |
| 8 locale files (`en/de/fr/es/ru/zh/ja/th.json`) | Removed `settings.tabs.payments` key and entire `settings.payments` block (7 keys x 8 locales = 56 keys removed) |

---

## Files Modified

| File | Type |
|------|------|
| `vbwd-backend/src/routes/admin/settings.py` | Removed mock payment-methods endpoint |
| `admin/vue/src/views/Settings.vue` | Template, script, and CSS cleanup |
| `admin/vue/tests/integration/Settings.spec.ts` | Test updates |
| `admin/vue/src/i18n/locales/{en,de,fr,es,ru,zh,ja,th}.json` | Removed 8 i18n keys each |

---

## Pre-commit Results

| Check | Status |
|-------|--------|
| Backend unit tests (`make test-unit`) | 594 passed, 4 skipped |
| Admin unit tests (`npx vitest run`) | 270 passed |
| User unit tests | 84 passed |
| Backend rebuild | api container rebuilt |
| Frontend rebuild | admin-app rebuilt |

---

## Design Decisions

1. **Root cause was backend route shadowing** — the mock in `settings.py` was registered before the real endpoint in `payment_methods.py`, so Flask always matched the mock first
2. **Keep standalone page only** — `/admin/payment-methods` has full CRUD capabilities vs the read-only Settings tab
3. **Settings now has 2 tabs** — "Core Settings" and "Token Bundles" (was 3 tabs)
4. **Clean removal** — All related template, script, CSS, tests, and i18n keys removed

---

## Test Totals After Sprint

| Component | Tests |
|-----------|-------|
| Backend | 594 passed |
| Frontend Admin | 270 passed |
| Frontend User | 84 passed |
| **Total** | **948** |
