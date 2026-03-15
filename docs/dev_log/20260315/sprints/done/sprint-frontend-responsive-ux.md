# Sprint: Frontend Responsive UX & Design System
**Date:** 2026-03-15
**Scope:** vbwd-fe-user, vbwd-fe-admin, vbwd-fe-core (docs)
**Status:** Completed

---

## Goal

Make every page in fe-user and fe-admin smartphone-vertical-ready, implement the admin burger menu matching the fe-user pattern, add the mobile cart icon in the user dashboard header, and document the fe-core design system for developers and end users.

---

## Tasks

### 1. Admin Burger Menu (Mobile Responsive Layout) ✅

**Files:** `vbwd-fe-admin/vue/src/layouts/AdminLayout.vue`, `AdminSidebar.vue`, `AdminTopbar.vue`

- `AdminLayout.vue`:
  - Mobile header (fixed 60px, `#2c3e50`): burger button + "VBWD Admin" title
  - `showMobileMenu` ref, `toggleMobileMenu()`, `closeMobileMenu()`
  - Passes `:show-mobile="showMobileMenu"` prop to `AdminSidebar`
  - Emits `@close="closeMobileMenu"` from sidebar
  - Dark semi-transparent overlay (`v-if="showMobileMenu"`) closes on click
  - `@media (≤1024px)`: mobile header shown, `margin-left: 0`, `margin-top: 60px`, padding 20px
  - `@media (≤768px)`: padding 15px

- `AdminSidebar.vue`:
  - Added `defineProps<{ showMobile?: boolean }>()` + `defineEmits<{ close: [] }>()`
  - `closeNav()` emits `close`
  - All `<router-link>` nav items call `@click="closeNav"` → auto-collapse on navigation
  - Profile link also calls `closeNav()`
  - `<aside :class="{ 'admin-sidebar-mobile-open': showMobile }">`
  - `@media (≤1024px)`: `position: fixed; top: 60px; transform: translateX(-100%); transition: 0.3s`; `.sidebar-brand` hidden
  - `.admin-sidebar-mobile-open`: `transform: translateX(0)`
  - `@media (≤768px)`: `width: 100%`

- `AdminTopbar.vue`:
  - Reduced padding/font at `≤1024px`

---

### 2. fe-user Mobile Cart Icon in Header ✅

**File:** `vbwd-fe-user/vue/src/layouts/UserLayout.vue`

- Mobile header has a cart button (top-right) with red dot badge when cart non-empty
- On click: navigates directly to checkout (`goToCheckout()`)
- Cart dropdown on desktop uses `position: absolute; bottom: 100%`
- Cart dropdown on mobile uses `position: fixed; top: 60px; right: 0` (always visible under header)
- `@click.stop` on cart and user-menu buttons (fixes "works on second click" bug — prevents propagation to document `handleClickOutside`)

---

### 3. main-content Overflow Fix ✅

**File:** `vbwd-fe-user/vue/src/layouts/UserLayout.vue`

Added to `@media (≤1024px)` on `.main-content`:
```css
width: 100%;
box-sizing: border-box;
overflow-x: hidden;
```
Prevents any child element from causing horizontal scroll on mobile.

---

### 4. fe-user Page Responsive CSS ✅

**`Subscription.vue`** — `@media (≤768px)`:
- `.card` padding reduced to 16px
- `.section-header` stacks vertically (search goes below heading)
- `.search-box input` → `width: 100%`
- `.no-subscription .btn` → `width: 100%`
- Modal actions stack and go full-width
- `.plan-header` wraps
- `.detail-row` wraps for long values
- Pagination wraps

**`InvoiceDetail.vue`** — `@media (≤768px)`:
- `max-width: 100%`
- Card padding 16px
- Invoice header stacks (number + status badge)
- Detail rows stack vertically
- `.line-items` gets `overflow-x: auto`, table `min-width: 480px`
- Actions stack, buttons go full-width

---

### 5. TarifPlanDetail.vue — Select Plan & Go Back ✅

**File:** `vbwd-fe-user/vue/src/views/TarifPlanDetail.vue`

Replaced the old `<router-link class="back-link">` with:
- `<button class="btn-back" @click="router.go(-1)">← Back</button>` — uses browser history so user returns to wherever they came from (plans list, subscription page, invoice line item, etc.)

Added after the tabs panel (only when `plan.is_active`):
```html
<div class="plan-actions">
  <router-link :to="`/dashboard/checkout/${plan.slug}`" class="btn-select-plan">
    Select Plan
  </router-link>
</div>
```
Routes to `name: checkout` with the plan's slug.

Added `@media (≤768px)`:
- `max-width: 100%`, padding 12px
- `plan-header` wraps
- `page-title` font-size reduced
- `pf-tabs__panel` padding 16px
- Meta grid → 2 columns
- `btn-select-plan` full-width

---

### 6. fe-core Design System Documentation ✅

**Files created:**

| File | Audience | Content |
|---|---|---|
| `vbwd-fe-core/docs/styling.md` | Developers | Full token reference, all components API, sidebar/burger pattern, theme switching, form rules, mobile app compat, extension guide |
| `vbwd-fe-user/docs/styling.md` | Developers + Users | Import path, layout, writing page styles, plugin rules; short user appearance guide |
| `vbwd-fe-admin/docs/styling.md` | Developers + Admins | Import path, layout, nav groups, token overrides, plugin views; short admin appearance guide |
| `docs/dev_log/20260315/reports/fe-core-design-system-report.md` | Team | Sprint report, token naming, gap analysis, breakpoints, theme-switching flow, test results |

---

## Responsive Breakpoints (Standard — both apps)

| Breakpoint | Sidebar | Main content | Padding |
|---|---|---|---|
| `> 1024px` (desktop) | Fixed 250px left | `margin-left: 250px` | 30px |
| `769–1024px` (tablet) | Hidden, slide-in | `margin-left: 0`, `margin-top: 60px` | 20px |
| `≤ 768px` (phone) | Full-width when open | Same as tablet | 15px |

---

## Design Token Contract

All components and views use `var(--vbwd-*)` CSS custom properties. Hardcoded colors are acceptable only as fallbacks: `var(--vbwd-color-primary, #3498db)`.

Theme switching = toggling `.dark` or custom class on `<html>` element.
All tokens documented in `vbwd-fe-core/docs/styling.md`.

---

## Test Results

- `vbwd-fe-user`: **389 / 389 passed**
- `vbwd-fe-admin`: **345 passed, 10 pre-existing failures** (unrelated to this sprint)

---

## Remaining / Follow-up

| Item | Priority |
|---|---|
| Extract `VbwdAppLayout` component to fe-core (unify UserLayout + AdminLayout) | High |
| `plans.selectPlan` i18n key in all 8 locales | Medium |
| Remaining 26 admin view files — `@media` responsive CSS | Medium |
| Appearance store (Pinia) in fe-user + admin profile appearance section | Medium |
| Mobile safe-area-inset (`env(safe-area-inset-*)`) for Capacitor/WebView | Medium |
| Harmonize `--vbwd-text-*` vs `--vbwd-color-text-*` token naming | Low |
