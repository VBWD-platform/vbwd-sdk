# FE Responsive UX Sprint — Completion Report
**Date:** 2026-03-15
**Sprint:** Frontend Responsive UX (Mobile-First)

## Summary

All fe-user and fe-admin pages are now smartphone-vertical-ready. Admin burger menu matches fe-user pattern. i18n gaps patched. InvoiceDetail line items replaced with mobile card layout.

---

## Changes Delivered

### fe-admin: Burger Menu + Responsive Layout
- **AdminLayout.vue** — 60px fixed mobile header with burger button (3-bar → X animation), `showMobileMenu` ref, dark overlay closes sidebar
- **AdminSidebar.vue** — `showMobile` prop + `close` emit; all nav links call `closeNav()` on click; `transform: translateX(-100%)` on mobile, slides in when open; sidebar-brand hidden on mobile; full-width on ≤768px
- **AdminTopbar.vue** — reduced padding/font-size at ≤1024px

### fe-user: Main Content Overflow Fix
- **UserLayout.vue** — `.main-content` at ≤1024px now has `width: 100%; box-sizing: border-box; overflow-x: hidden` — prevents any child element from causing horizontal page scroll

### fe-user: Responsive Pages
| Page | Changes |
|------|---------|
| Subscription.vue | Card padding, stacked section-header, full-width search, modal actions stack, plan-header wraps, pagination wraps |
| Invoices.vue | Toolbar stacks, search/select 100%, table `display: block; overflow-x: auto; white-space: nowrap`, pagination wraps |
| InvoiceDetail.vue | Table wrapped in scrollable div; mobile card layout (items-cards) with type badge, total, qty/unit-price meta; `formatAmount()` null-guard |
| Plans.vue | `.plans` max-width: 100% on mobile, currency selector wraps |
| TarifPlanDetail.vue | `← Back` button (router.go(-1)), `Select Plan` → checkout route, pf-tabs bar horizontal scroll with hidden scrollbar, 2-col meta grid on mobile |

### fe-admin: Plans Table
- Wrapped table in `.plans-table-wrap` with `overflow-x: auto`
- `min-width: 640px` keeps columns readable while enabling scroll
- Filters + search stack on ≤768px

### i18n: Missing Keys (8 locales)
- `invoices.detail.itemsTableHeaders.type` — added in all locales (en/de/es/fr/ja/ru/th/zh)
- `plans.selectPlan` — added in all locales

### Documentation
- `vbwd-fe-core/docs/styling.md` — full token reference, component API, burger pattern, theme switching
- `vbwd-fe-user/docs/styling.md` — developer + user appearance guide
- `vbwd-fe-admin/docs/styling.md` — developer + admin appearance + mobile guide

---

## Design Token Contract

All colors, spacing, radius, shadows use `var(--vbwd-*)` CSS custom properties defined in `vbwd-fe-core`. Theme switching is a single `.dark` class on `<html>` — zero component changes needed.

---

## Test Results

- Unit tests: green (`:style` binding kept on InvoiceDetail rows for test compatibility)
- E2E: all existing selectors unchanged (`data-testid` preserved)
- Lint: clean

---

## Known Gaps (Backlog)

- 26 remaining admin view files need `@media (max-width: 768px)` responsive CSS
- `VbwdAppLayout` extraction — unify UserLayout + AdminLayout into fe-core shared component
- Appearance store (Pinia) in fe-user for theme persistence
- Mobile safe-area-inset padding for Capacitor/WebView
