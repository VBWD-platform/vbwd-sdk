# Report 07 — Sprint 05: Extensible Admin Sidebar

**Date:** 2026-03-28
**Status:** Done

---

## What Was Done

Made all core sidebar sections extensible from plugins via a section slot system in `ExtensionRegistry`.

### New Capabilities

- **`sectionItems`** — plugins inject items into core sections (Sales, Settings) by ID
- **`hiddenItems`** — plugins hide any core nav item by route path
- **`sectionComponents`** — plugins inject Vue components into sections (future-ready)
- **`buildSidebar()`** — single method merges core + plugin items with position control
- **`children`** on NavItem — 3-level nav support (L0 sections → L1 items → L2 children)
- **Position hints** — `before:invoices`, `after:users`, `start`, `end` (default: `end`)

### Files Changed

| File | Change |
|------|--------|
| `vue/src/plugins/extensionRegistry.ts` | Added `NavItemWithPosition`, `SectionComponent`, `sectionItems`, `hiddenItems`, `sectionComponents`, `buildSidebar()`, `getSectionItems()`, `getHiddenItems()`, `getSectionComponents()` |
| `vue/src/layouts/AdminSidebar.vue` | Fully refactored — data-driven via `buildSidebar()`, zero hardcoded plugin references, 3-level nav rendering with Level 2 toggle |
| `plugins/subscription-admin/index.ts` | Changed from `navSections` to `sectionItems.sales` for "Subscriptions" |
| `vue/tests/unit/plugins/extension-registry.spec.ts` | 18 new tests |

### Test Results

- 18 new registry tests (all green)
- 320 total unit tests (32 files, all green)
- ESLint + TypeScript: PASS
- `pre-commit-check.sh --full`: ALL CHECKS PASSED

### Subscription-admin Plugin — Before/After

**Before:** Subscriptions appeared as a separate standalone sidebar section.

**After:** "Subscriptions" is injected into the Sales section (before Invoices), and "Tarifs" (Plans, Add-Ons) remains as its own section:

```
▼ Sales
    Users
    Subscriptions  ← injected by subscription-admin plugin
    Invoices
▼ Tarifs           ← standalone section from subscription-admin plugin
    Plans
    Add-Ons
▼ Bookings         ← standalone section from booking plugin
    Dashboard
    All Bookings
    Resources
```
