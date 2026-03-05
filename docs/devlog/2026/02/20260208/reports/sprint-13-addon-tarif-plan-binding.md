# Sprint 13 Report — Add-On Tariff Plan Binding

**Date:** 2026-02-08
**Status:** COMPLETED
**Priority:** HIGH

---

## Summary

Added optional many-to-many relationship between add-ons and tariff plans. Add-ons can now be:
- **Independent** (no plan restriction) — visible to all users
- **Plan-specific** (bound to one or more plans) — visible only to subscribers of those plans

---

## Changes

### Backend

| File | Change |
|------|--------|
| `alembic/versions/20260208_add_addon_tarif_plans_table.py` | New migration: `addon_tarif_plans` junction table |
| `src/models/addon.py` | Added `addon_tarif_plans` table, `tarif_plans` relationship, `is_independent` property, updated `to_dict()` |
| `src/models/__init__.py` | Export `addon_tarif_plans` |
| `src/repositories/addon_repository.py` | Added `find_available_for_plan(plan_id)` — returns independent + plan-specific addons |
| `src/routes/admin/addons.py` | Handle `tarif_plan_ids` in POST/PUT, validate plan IDs exist |
| `src/routes/addons.py` | Added `@optional_auth`, auto-detect user's active subscription plan, filter with `find_available_for_plan()` |

### Frontend — Admin

| File | Change |
|------|--------|
| `stores/addons.ts` | Added `tarif_plan_ids` and `tarif_plans` to `AdminAddon` and `CreateAddonData` interfaces |
| `views/AddonForm.vue` | Added checkbox group for plan selection (fetches plans from planAdmin store) |
| `views/AddOns.vue` | Added "Plans" column with plan name badges (or "All Plans" for independent) |
| 8 locale files | Added 5 new i18n keys: `restrictToPlans`, `restrictToPlansHint`, `noPlansAvailable`, `allPlans`, `plans` |

### Frontend — User

| File | Change |
|------|--------|
| `views/AddOns.vue` | Updated interface with `tarif_plan_ids`/`tarif_plans`, filtering uses `tarif_plan_ids` instead of `conditions.subscription_parent` |

---

## Tests Added

### Backend — 22 new tests (583 total, 4 skipped)

| File | Tests |
|------|-------|
| `tests/unit/models/test_addon_tarif_plans.py` | 9 tests: junction table structure, relationship definition, `is_independent` property, `to_dict()` fields, column defaults |
| `tests/unit/routes/test_admin_addon_plans.py` | 7 tests: create with plan IDs, create without plan IDs, invalid plan IDs, update set/clear/invalid plans, GET includes plan data |
| `tests/unit/routes/test_public_addon_plans.py` | 4 tests: unauthenticated user, authenticated with subscription, authenticated without subscription, response structure |

### Frontend Admin — 13 new tests (265 total)

| File | Tests |
|------|-------|
| `tests/unit/stores/addons.spec.ts` | 3 tests: create/update with `tarif_plan_ids`, fetch includes plan data |
| `tests/unit/views/addon-form.spec.ts` | 6 tests: plan checkboxes render, unchecked by default, reflect saved values, toggle updates, submit includes IDs, no plans message |
| `tests/unit/views/addons.spec.ts` | 4 tests: Plans column header, "All Plans" badge, plan name badges, multiple plan badges |

### Frontend User — 6 new tests (78 total)

| File | Tests |
|------|-------|
| `tests/unit/views/addons-plan-filter.spec.ts` | 6 tests: separates independent/plan-specific, empty tarif_plan_ids = global, tarif_plan_ids = subscription, mixed, legacy compat, inactive filtered |

---

## Pre-commit Results

| Check | Status |
|-------|--------|
| Backend unit tests (`make test-unit`) | 583 passed, 4 skipped |
| Admin pre-commit (`--admin --unit`) | 265 passed, all checks passed |
| User pre-commit (`--user --unit`) | 78 passed, all checks passed |

---

## Design Decisions

1. **Users with no subscription** see independent add-ons only
2. **Admin plan selector** is a checkbox list of all active plans
3. **Admin list display** shows plan name badges per row (or "All Plans")
4. **Public API** auto-detects user's plan from active subscription (no explicit `plan_id` param needed)
5. **Backward compatible** — add-ons without `tarif_plan_ids` treated as independent

---

## Test Totals After Sprint

| Component | Tests |
|-----------|-------|
| Backend | 583 passed |
| Frontend Admin | 265 passed |
| Frontend User | 78 passed |
| **Total** | **926** |
