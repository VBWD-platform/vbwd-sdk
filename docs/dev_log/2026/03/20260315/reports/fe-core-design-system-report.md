# Report: fe-core Design System — Styles, Theming & Responsive Layout
**Date:** 2026-03-15
**Scope:** vbwd-fe-core, vbwd-fe-user, vbwd-fe-admin

---

## 1. Current State

`vbwd-fe-core` already contains a solid design system foundation:

- **`src/styles/variables.css`** — ~80 CSS custom properties covering colors, surfaces, shadows, radii, transitions, sidebar tokens, container sizing
- **`src/styles/index.css`** — Utility classes (typography, spacing, display, flex), resets
- **`src/components/ui/`** — 11 ready-to-use components: `Button`, `Input`, `Card`, `Table`, `Modal`, `Badge`, `Alert`, `Dropdown`, `Pagination`, `Spinner`, `DetailGrid/Field`
- **`src/components/layout/`** — `Container`, `Row`, `Col`
- **Dark mode** — `.dark` class on `<html>` overrides all surface/text/border tokens; fully implemented

Both `fe-user` and `fe-admin` import styles via `vbwd-view-component`. All components use `var(--vbwd-*)` properties internally.

---

## 2. Work Completed This Sprint (2026-03-15)

### Admin Burger Menu (Mobile Responsive Layout)
- **`AdminLayout.vue`** — Added mobile header (fixed 60px, `#2c3e50`) with burger button + "VBWD Admin" title; manages `showMobileMenu` ref; passes it as `:show-mobile` prop to `AdminSidebar`; renders dark overlay on mobile
- **`AdminSidebar.vue`** — Added `showMobile` prop + `close` emit; all `<router-link>` nav items call `closeNav()` on click; added CSS: `position: fixed; transform: translateX(-100%)` on `≤ 1024px`, `translateX(0)` when `.admin-sidebar-mobile-open`; full-width on `≤ 768px`; `sidebar-brand` hides on mobile (already shown in mobile header)
- **`AdminTopbar.vue`** — Reduced padding/font-size on `≤ 1024px`

### fe-user Responsive Fixes
- **`Subscription.vue`** — Added `@media (max-width: 768px)`: section-header stacks, search input full-width, cards reduce padding, no-subscription button full-width, modal actions stack, pagination wraps
- **`InvoiceDetail.vue`** — Added `@media (max-width: 768px)`: invoice-header stacks, detail-rows stack, items-table wrapped in overflow-x container (`min-width: 480px`), actions stack full-width

### Documentation Created
- `vbwd-fe-core/docs/styling.md` — Full developer reference (tokens table, all components, sidebar/burger pattern, theme switching, form rules, mobile app compatibility, extension guide)
- `vbwd-fe-user/docs/styling.md` — Developer guide (import path, layout, writing page styles, plugin rules) + short user guide (appearance switcher)
- `vbwd-fe-admin/docs/styling.md` — Developer guide (layout, nav groups, token overrides, plugin views) + short admin guide (appearance + mobile use)

---

## 3. Token Naming Conventions

All custom properties follow the pattern `--vbwd-{category}-{role}[-{modifier}]`:

```
--vbwd-color-primary
--vbwd-color-primary-light
--vbwd-color-primary-dark
--vbwd-sidebar-bg
--vbwd-sidebar-text
--vbwd-sidebar-active-bg
--vbwd-page-bg
--vbwd-card-bg
--vbwd-text-heading      (used in older view files — target for harmonization)
--vbwd-text-body         (used in older view files)
--vbwd-text-muted        (used in older view files)
--vbwd-border-color      (used in older view files)
--vbwd-border-light      (used in older view files)
```

**Note:** Two naming sub-patterns currently coexist:
- Core library: `--vbwd-color-text`, `--vbwd-color-border` (new, Tailwind-inspired)
- Legacy view files: `--vbwd-text-heading`, `--vbwd-border-color` (older)

Both patterns are declared in `variables.css`. A future normalization pass should consolidate to one scheme.

---

## 4. Gaps & Planned Work

| Gap | Priority | Notes |
|---|---|---|
| `VbwdAppLayout` shared component | High | UserLayout + AdminLayout share 80% logic; extract to fe-core |
| Inline hardcoded colors in view files | Medium | ~40 view files still use `#2c3e50`, `#27ae60` etc. directly |
| `--vbwd-text-*` vs `--vbwd-color-text-*` naming | Low | Harmonize after VbwdAppLayout extraction |
| Mobile safe-area-inset padding | Medium | Add to app root for Capacitor/WebView |
| Appearance store in fe-user | High | `appearance.ts` Pinia store for theme persistence |
| Admin appearance setting | Medium | Profile page → Appearance section |
| Remaining admin view responsive CSS | Medium | 26 admin views need `@media (max-width: 768px)` |

---

## 5. Responsive Breakpoints (Standard)

| Breakpoint | Applies at | Behavior |
|---|---|---|
| Desktop | `> 1024px` | Sidebar fixed 250px, full layout |
| Tablet | `769px – 1024px` | Burger menu, sidebar hidden/slide-in |
| Mobile | `≤ 768px` | Sidebar full-width when open, stacked layouts, scrollable tables |

---

## 6. Theme Switching — How It Works

```
User selects theme
       ↓
appearance store calls applyTheme('dark')
       ↓
document.documentElement.classList.add('dark')
       ↓
CSS: .dark { --vbwd-color-background: #111827; … }
       ↓
All components re-render with new token values
(zero JS, zero component prop changes needed)
```

Custom themes work identically using a custom class (`theme-corporate`, `theme-green`, etc.) with their own `--vbwd-*` overrides.

---

## 7. Test Results

- `vbwd-fe-user`: **389 / 389 passed** (no regression)
- `vbwd-fe-admin`: **345 passed, 10 pre-existing failures** (no regression from this sprint's changes)
