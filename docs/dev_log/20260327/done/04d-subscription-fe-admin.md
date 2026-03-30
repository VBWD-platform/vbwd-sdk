# Sprint 04d — Subscription Admin Frontend Plugin

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Create `subscription-admin` plugin for fe-admin. Move all plan/subscription/add-on/category views, stores, and routes from core `vue/src/` into the plugin.

---

## Plugin Structure

```
plugins/subscription-admin/          (standalone GitHub repo: vbwd-fe-admin-plugin-subscription)
├── src/
│   ├── views/
│   │   ├── Plans.vue
│   │   ├── PlanForm.vue
│   │   ├── CategoryForm.vue
│   │   ├── AddOns.vue
│   │   ├── AddonForm.vue
│   │   ├── Subscriptions.vue
│   │   ├── SubscriptionDetails.vue
│   │   └── SubscriptionCreate.vue
│   ├── components/
│   │   └── CategoriesTab.vue
│   └── stores/
│       ├── planAdmin.ts
│       ├── subscriptions.ts
│       ├── addons.ts
│       └── categoryAdmin.ts
├── locales/
│   └── en.json
├── index.ts                          Plugin registration (routes, stores, nav items)
├── admin-config.json
├── config.json
├── tests/
│   └── unit/
└── README.md
```

---

## Routes Registered by Plugin

```typescript
sdk.addRoute({ path: '/admin/plans', component: Plans })
sdk.addRoute({ path: '/admin/plans/new', component: PlanForm })
sdk.addRoute({ path: '/admin/plans/:id/edit', component: PlanForm })
sdk.addRoute({ path: '/admin/plans/categories/new', component: CategoryForm })
sdk.addRoute({ path: '/admin/plans/categories/:id/edit', component: CategoryForm })
sdk.addRoute({ path: '/admin/add-ons', component: AddOns })
sdk.addRoute({ path: '/admin/add-ons/new', component: AddonForm })
sdk.addRoute({ path: '/admin/add-ons/:id/edit', component: AddonForm })
sdk.addRoute({ path: '/admin/subscriptions', component: Subscriptions })
sdk.addRoute({ path: '/admin/subscriptions/create', component: SubscriptionCreate })
sdk.addRoute({ path: '/admin/subscriptions/:id', component: SubscriptionDetails })
```

## Nav Items Registered by Plugin

- **Sales** section: "Subscriptions" (icon: credit-card)
- **Tarifs** section: "Plans" (icon: tag), "Add-Ons" (icon: puzzle)

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create plugin skeleton + `index.ts` with route/store/nav registration | — |
| 2 | Move views from `vue/src/views/` to `plugins/subscription-admin/src/views/` | — |
| 3 | Move stores from `vue/src/stores/` to `plugins/subscription-admin/src/stores/` | — |
| 4 | Move `CategoriesTab.vue` component | — |
| 5 | Update all import paths in moved files | — |
| 6 | Add i18n translations to `locales/en.json` | — |
| 7 | Remove moved files from `vue/src/` | — |
| 8 | Remove subscription/plan/addon routes from `vue/src/router/index.ts` | — |
| 9 | Remove subscription/plan/addon nav items from `AdminSidebar.vue` | — |
| 10 | Register in `plugins/plugins.json` + `plugins/config.json` | — |
| 11 | Add `plugins/subscription-admin/` to `.gitignore` | — |
| 12 | Unit tests | Plugin unit tests |
| 13 | `pre-commit-check.sh` — all green | — |

---

## What Gets Removed from fe-admin Core

### Views (delete from `vue/src/views/`)
- `Plans.vue`, `PlanForm.vue`, `CategoryForm.vue`
- `AddOns.vue`, `AddonForm.vue`
- `Subscriptions.vue`, `SubscriptionDetails.vue`, `SubscriptionCreate.vue`

### Stores (delete from `vue/src/stores/`)
- `planAdmin.ts`, `subscriptions.ts`, `addons.ts`, `categoryAdmin.ts`

### Components (delete from `vue/src/components/`)
- `CategoriesTab.vue`

### Router (update `vue/src/router/index.ts`)
- Remove all `/admin/plans/*`, `/admin/add-ons/*`, `/admin/subscriptions/*` routes

### Sidebar (update `AdminSidebar.vue`)
- Remove "Subscriptions", "Plans", "Add-Ons" nav items

---

## Acceptance Criteria

- Plugin renders all plan/subscription/addon admin pages
- Core `vue/src/` has zero subscription/plan/addon files
- Admin sidebar shows subscription items only when plugin is enabled
- All existing admin tests pass
- `pre-commit-check.sh` passes
