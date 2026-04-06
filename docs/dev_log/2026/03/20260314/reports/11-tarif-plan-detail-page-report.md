# Sprint 11 — Tarif Plan Detail Page — Completion Report

**Status:** ✅ Done
**Completed:** 2026-03-15

---

## Summary

Implemented the full tariff plan detail page with plugin-extensible tabs, plus GHRM plugin integration and fe-admin invoice fix.

---

## Deliverables

### Backend — GHRM `by-plan` endpoint

| File | Change |
|------|--------|
| `plugins/ghrm/src/repositories/software_package_repository.py` | Added `find_by_tariff_plan_id(plan_id)` with UUID validation |
| `plugins/ghrm/src/services/software_package_service.py` | Added `get_by_tariff_plan_id(plan_id)` |
| `plugins/ghrm/src/routes.py` | Added `GET /api/v1/packages/by-plan/<plan_id>` route (public, no auth required) |
| `plugins/ghrm/tests/unit/test_package_by_plan.py` | 8 new unit tests |

### fe-user — Plan detail page + GHRM tabs

| File | Change |
|------|--------|
| `vue/src/views/Subscription.vue` | Added `goToPlan()`, clickable subscription rows, `@click.stop` on actions cell |
| `vue/src/router/index.ts` | Added `/dashboard/tarif/:planSlug` route → `TarifPlanDetail.vue` |
| `vue/src/utils/planDetailTabRegistry.ts` | New singleton tab registry (`PlanDetailTab[]`) for plugin extension |
| `vue/src/views/TarifPlanDetail.vue` | New plan detail view: `pf-tabs` pattern, `--vbwd-*` CSS vars, `tarif-plan-detail` wrapper |
| `plugins/ghrm/src/api/ghrmApi.ts` | Added `getPackageByPlan(planId)` |
| `plugins/ghrm/src/components/GhrmPlanSoftwareTab.vue` | New: 5 sub-tabs (Overview, Screenshots, Changelog, Docs, Versions), reuses existing GHRM components |
| `plugins/ghrm/src/components/GhrmPlanGithubAccessTab.vue` | New: GitHub OAuth connect button + clone/pull/fetch commands when connected |
| `plugins/ghrm/index.ts` | Registers "Software" and "GitHub Access" tabs in `install()` via `planDetailTabRegistry` |
| `vue/tests/unit/views/tarif-plan-detail.spec.ts` | 7 new unit tests |
| `vue/tests/unit/plugins/ghrm-plan-software-tab.spec.ts` | 4 new unit tests |
| `vue/tests/unit/plugins/ghrm-plan-github-access-tab.spec.ts` | 5 new unit tests |

### fe-admin — Invoice line item click fix

| File | Change |
|------|--------|
| `vue/src/views/InvoiceDetails.vue` | Fixed `itemLink()` case mismatch (`item.type.toUpperCase()`), made `<tr>` rows clickable with `@click="navigateTo(itemLink(item))"` |
| `vue/tests/unit/views/invoice-details-line-items.spec.ts` | 10 new unit tests |

---

## Test Results

| Repo | Tests | Result |
|------|-------|--------|
| vbwd-backend | 57 GHRM unit tests | ✅ Pass |
| vbwd-fe-user | 303 unit tests | ✅ Pass |
| vbwd-fe-admin | 219 unit tests | ✅ Pass |

---

## Key Design Decisions

- **`planDetailTabRegistry`** — Open/Closed principle: core page is agnostic, GHRM registers tabs at boot. No core → plugin imports.
- **`pf-tabs` CSS** — Reuses same tab bar class pattern as `fe-admin` plan edit page.
- **`--vbwd-*` CSS variables** — All new views use theme-switcher-compatible tokens; no hardcoded hex colors.
- **`tarif-plan-detail` wrapper class** — Matches `plan-form-view` convention on fe-admin plan edit page.
- **Anonymous checkout** — `handleGetPackage()` goes directly to `/checkout` without auth check (same as "Choose Plan" on pricing page).
- **`itemLink()` fix** — API returns uppercase type strings (`SUBSCRIPTION`), switch cases now use `.toUpperCase()`.
