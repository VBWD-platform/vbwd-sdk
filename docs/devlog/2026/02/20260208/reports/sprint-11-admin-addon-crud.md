# Sprint 11 Report — Admin Add-On CRUD Management

**Status:** DONE
**Duration:** ~20 minutes
**Date:** 2026-02-08

---

## Summary

Replaced the placeholder Add-Ons admin page with a fully functional CRUD interface: Pinia store, list view with search/sort/actions, create/edit form, router routes, and i18n in all 8 languages.

## Results

| Sub-sprint | Description | Tests | Result |
|-----------|-------------|-------|--------|
| 11a — Addon Store | `addons.ts` Pinia store | 12 | All GREEN |
| 11b — List View | `AddOns.vue` with table, search, sort, actions | 12 | All GREEN |
| 11c — Form View | `AddonForm.vue` create/edit with validation | 17 | All GREEN |
| 11d — Router | `addon-new` + `addon-edit` routes | implicit | Router entries added |
| 11e — i18n | 35 keys in all 8 languages (EN, DE, FR, ES, RU, ZH, JA, TH) | implicit | Key structure identical |

**Total new tests:** 41

## Files Created

| File | Description |
|------|-------------|
| `admin/vue/src/stores/addons.ts` | Pinia store: fetchAddons, fetchAddon, createAddon, updateAddon, deleteAddon, activateAddon, deactivateAddon, reset |
| `admin/vue/src/views/AddonForm.vue` | Create/edit form: name, slug, description, price, currency, billing period, config (JSON), sort order, activate/deactivate/delete |
| `admin/vue/tests/unit/stores/addons.spec.ts` | 12 store unit tests |
| `admin/vue/tests/unit/views/addons.spec.ts` | 12 list view unit tests |
| `admin/vue/tests/unit/views/addon-form.spec.ts` | 17 form view unit tests |

## Files Modified

| File | Change |
|------|--------|
| `admin/vue/src/views/AddOns.vue` | Replaced placeholder tabs with full list view: table, search, sort, status badges, activate/deactivate/delete actions |
| `admin/vue/src/router/index.ts` | Added `add-ons/new` (addon-new) and `add-ons/:id/edit` (addon-edit) routes |
| `admin/vue/src/i18n/locales/en.json` | Replaced addOns section: 5 placeholder keys → 35 CRUD keys |
| `admin/vue/src/i18n/locales/de.json` | Same structure, German translations |
| `admin/vue/src/i18n/locales/fr.json` | Same structure, French translations |
| `admin/vue/src/i18n/locales/es.json` | Same structure, Spanish translations |
| `admin/vue/src/i18n/locales/ru.json` | Same structure, Russian translations |
| `admin/vue/src/i18n/locales/zh.json` | Same structure, Chinese translations |
| `admin/vue/src/i18n/locales/ja.json` | Same structure, Japanese translations |
| `admin/vue/src/i18n/locales/th.json` | Same structure, Thai translations |

## Test Counts After Sprint

| Location | Before | After | Delta |
|----------|--------|-------|-------|
| `admin/vue/tests/unit/stores/` | 0 (addons) | 12 | +12 |
| `admin/vue/tests/unit/views/` | 3 | 32 | +29 |
| **Admin total** | 211 | 252 | +41 |
| User total | 51 | 51 | 0 |
| **Total** | 313 | 354 | +41 |

## Regression Check

- Admin: 252/252 pass
- User: 51/51 pass

## Key Design Decisions

1. **Follows Plans pattern exactly** — AddOns.vue mirrors Plans.vue, AddonForm.vue mirrors PlanForm.vue, addons.ts mirrors planAdmin.ts
2. **API mock strategy in view tests** — Mock `api.get` return value before `mount()` to let `onMounted`'s `fetchAddons()` populate store naturally
3. **vue-i18n mock** — `vi.mock('vue-i18n')` returns key strings for predictable test assertions
4. **Config as JSON textarea** — monospace textarea with `JSON.stringify`/`JSON.parse` for flexible addon parameters
5. **Currency select** — EUR (default), USD, GBP
6. **Billing period** — monthly, yearly, one_time (matches backend enum)

## Principles Applied

| Principle | How Applied |
|-----------|------------|
| TDD | Store tests first, then implementation; view tests first, then views |
| SRP | Store manages state, views render/handle input, router handles navigation |
| LSP | AddonForm behaves identically to PlanForm from user perspective |
| DRY | Same CSS patterns, same form layout, same error handling as Plans |
| DIP | Views depend on store abstraction, store depends on api abstraction |
| No Overengineering | Simple table + form, no abstract base, no generic CRUD factory |
