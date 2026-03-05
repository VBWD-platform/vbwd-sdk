# Sprint 14 Report — Add-On Management (Admin History Tab + User Detail/Cancel)

**Date:** 2026-02-08
**Status:** DONE
**Priority:** HIGH

---

## Summary

Two related features:
1. **Admin**: Added "Add-ons" tab to UserEdit page showing addon subscription history with payment status, active/inactive status, and clickable invoice links
2. **User**: Made dashboard add-ons clickable, new AddonDetail page with subscription details and cancellation flow

---

## Changes

### Backend

| File | Change |
|------|--------|
| `src/routes/admin/users.py` | Added `GET /<user_id>/addons` endpoint — returns addon subscriptions with invoice data |
| `src/routes/user.py` | Added `GET /addons/<id>` (detail) and `POST /addons/<id>/cancel` (cancellation with ownership check) |

### Frontend — Admin

| File | Change |
|------|--------|
| `src/views/UserEdit.vue` | Added 4th "Add-ons" tab with table (addon name, payment badge, status badge, invoice links), search filter, lazy loading |
| 8 locale files (`en/de/fr/es/ru/zh/ja/th.json`) | Added 6 new i18n keys: `addons`, `addonName`, `paymentStatus`, `firstInvoice`, `lastInvoice`, `noAddonsForUser` |

### Frontend — User

| File | Change |
|------|--------|
| `src/router/index.ts` | Added `/add-ons/:id` route for addon-detail |
| `src/stores/subscription.ts` | Added `fetchAddonDetail()` and `cancelAddon()` actions |
| `src/views/AddonDetail.vue` | NEW: detail page with addon info, status badges, invoice section, cancel flow with confirmation dialog |
| `src/views/Dashboard.vue` | Wrapped addon items in `<router-link>` with hover effects |
| `src/i18n/locales/en.json` | Added 14 new keys (`addons.detail.*` + `common.confirm`) |
| `src/i18n/locales/de.json` | Added 14 new keys (matching EN structure) |

---

## Tests Added

### Backend — 11 new tests (594 total, 4 skipped)

| File | Tests |
|------|-------|
| `tests/unit/routes/test_admin_user_addons.py` | 5 tests: returns addon subs, empty list, includes invoice data, 404 for non-existent user, requires admin auth |
| `tests/unit/routes/test_user_addon_detail.py` | 6 tests: GET detail with addon/invoice info, 404 non-existent, 403 other user, POST cancel active, cancel fails for cancelled, cancel 403 other user |

### Frontend Admin — 6 new tests (271 total)

| File | Tests |
|------|-------|
| `tests/unit/views/user-edit-addons.spec.ts` | 6 tests: tab button renders, clicking tab fetches data, table renders addons, payment badge, invoice links clickable, empty state |

### Frontend User — 6 new tests (84 total)

| File | Tests |
|------|-------|
| `tests/unit/views/addon-detail.spec.ts` | 6 tests: renders addon details (name/description/price), active status badge, cancel button visible for active, hidden for cancelled, confirmation dialog works, back-to-dashboard link |

---

## Pre-commit Results

| Check | Status |
|-------|--------|
| Backend unit tests (`make test-unit`) | 594 passed, 4 skipped |
| Admin unit tests (`make test`) | 271 passed |
| User unit tests | 84 passed |
| Frontend rebuild | user-app + admin-app rebuilt successfully |
| i18n parity (EN/DE user) | 344 keys each, matched |

---

## Design Decisions

1. **Admin addons tab** uses lazy loading — data fetched only when tab is clicked
2. **Invoice links** navigate to existing admin invoice detail page
3. **Cancel flow** requires confirmation dialog before proceeding
4. **Ownership check** on both GET detail and POST cancel prevents accessing other users' addons
5. **Only active/pending** addons can be cancelled (cancelled/expired return 400)
6. **Dashboard links** use `<router-link>` for SPA navigation without page reload

---

## Test Totals After Sprint

| Component | Tests |
|-----------|-------|
| Backend | 594 passed |
| Frontend Admin | 271 passed |
| Frontend User | 84 passed |
| **Total** | **949** |
