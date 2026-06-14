# S72.1 — Dedicated "Taxes & Countries" settings page

**Part of:** [S72 — Taxes & Countries (umbrella)](s72-taxes.md) · **Area:** `vbwd-fe-admin` only · **Depends on:** existing Countries tab (`useCountriesStore`) + Taxes tab (`useTaxAdminStore`).
**Engineering requirements:** TDD-first, SOLID/DRY, no overengineering; fe-admin Vitest + ESLint green. See umbrella for grounding. **Not committed.**

## Problem
Countries and Taxes are managed as **inline tabs** inside the already-crowded main Settings page (`vue/src/views/Settings.vue`: `countries-content`, `tax-content`). They belong together on their own page.

## Goal
A new Settings sub-item **"Taxes & Countries"** at `/admin/settings/tax-and-countries` hosting both, removed from the main Settings page. Behaviour of the two tabs is unchanged.

## Scope (fe-admin)
1. **Extract** the inline tabs from `Settings.vue` into standalone components, behaviour/stores/APIs/`data-testid`s unchanged:
   - `vue/src/views/tax-countries/CountriesTab.vue` (enabled/disabled two-panel, `useCountriesStore`, `/admin/countries*`).
   - `vue/src/views/tax-countries/TaxesTab.vue` (Tax Classes + Tax Rates CRUD, `useTaxAdminStore`, `/admin/tax/classes` + `/admin/tax/rates`).
2. **New page** `vue/src/views/TaxAndCountriesSettings.vue` — two sub-tabs (Countries | Taxes) mounting the extracted components. **Remove** both tabs + their now-dead inline code from `Settings.vue`.
3. **Route** (`vue/src/router/index.ts`): `{ path: 'settings/tax-and-countries', name: 'tax-and-countries', component: () => import('@/views/TaxAndCountriesSettings.vue'), meta: { requiredPermission: 'settings.manage' } }`.
4. **Nav** (`vue/src/layouts/AdminSidebar.vue`, core `settings` section): add `{ label: t('nav.taxesAndCountries'), to: '/admin/settings/tax-and-countries', id: 'taxes-and-countries', requiredPermission: 'settings.manage' }` → auto test-id `nav-item-taxes-and-countries`.
5. i18n: `nav.taxesAndCountries`, page + sub-tab titles (all locales).

## TDD (Vitest)
- The nav item renders (perm-gated) and routes to the page; the page shows both sub-tabs.
- Countries enable/disable/reorder and Tax class/rate CRUD still work from the new page (re-point the existing tab specs).
- `Settings.vue` no longer renders `countries-content` / `tax-content`.

## Definition of done
Countries + Taxes live on `/admin/settings/tax-and-countries` (nav sub-item + route, `settings.manage`), removed from the main Settings page, behaviour unchanged; fe-admin Vitest + ESLint green. Not committed.
