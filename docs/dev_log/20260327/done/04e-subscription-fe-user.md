# Sprint 04e — Subscription User Frontend Plugin

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Create `subscription` plugin for fe-user. Move all plan/subscription/add-on/checkout views, stores, and routes from core `vue/src/` into the plugin. Core dashboard retains only: profile, token activity, recent invoices. Plugin extends dashboard with subscription/addon blocks.

---

## Plugin Structure

```
plugins/subscription/                 (standalone GitHub repo: vbwd-fe-user-plugin-subscription)
├── subscription/
│   ├── views/
│   │   ├── Plans.vue
│   │   ├── PlanDetailView.vue
│   │   ├── TarifPlanDetail.vue
│   │   ├── Subscription.vue
│   │   ├── AddOns.vue
│   │   ├── AddonDetail.vue
│   │   ├── AddonInfoView.vue
│   │   └── Checkout.vue
│   ├── components/
│   │   ├── DashboardSubscriptionCard.vue     dashboard extension: active subscription
│   │   ├── DashboardSubscriptionHistory.vue  dashboard extension: subscription history
│   │   ├── DashboardAddOnsBlock.vue          dashboard extension: add-ons
│   │   └── checkout/
│   │       ├── BillingAddressBlock.vue
│   │       ├── EmailBlock.vue
│   │       ├── PaymentMethodsBlock.vue
│   │       └── TermsCheckbox.vue
│   └── stores/
│       ├── plans.ts
│       ├── subscription.ts
│       └── checkout.ts
├── locales/
│   └── en.json
├── index.ts                          Plugin registration
├── admin-config.json
├── config.json
├── tests/
│   └── unit/
└── README.md
```

---

## Routes Registered by Plugin

```typescript
sdk.addRoute({ path: '/dashboard/plans', component: Plans })
sdk.addRoute({ path: '/dashboard/plans/:planId', component: PlanDetailView })
sdk.addRoute({ path: '/dashboard/plan/:planSlug', component: TarifPlanDetail })
sdk.addRoute({ path: '/dashboard/subscription', component: Subscription })
sdk.addRoute({ path: '/dashboard/add-ons', component: AddOns })
sdk.addRoute({ path: '/dashboard/add-ons/info/:addonId', component: AddonInfoView })
sdk.addRoute({ path: '/dashboard/add-ons/:id', component: AddonDetail })
sdk.addRoute({ path: '/dashboard/checkout/cart', component: Checkout })
sdk.addRoute({ path: '/dashboard/checkout/:planSlug', component: Checkout })
```

## Dashboard Extensions

Plugin registers dashboard widgets via `sdk.addComponent()`:

```typescript
sdk.addComponent('DashboardSubscriptionCard', DashboardSubscriptionCard)
sdk.addComponent('DashboardSubscriptionHistory', DashboardSubscriptionHistory)
sdk.addComponent('DashboardAddOnsBlock', DashboardAddOnsBlock)
```

Core Dashboard.vue renders these dynamically if the components are registered.

## Nav Items Registered by Plugin

- **Store** group: "Plans", "Add-Ons"
- **Subscription** group: "Subscription"

---

## Core Dashboard After Extraction

```vue
<!-- Dashboard.vue (core) — only these blocks remain -->
<ProfileCard />
<TokenActivityBlock />
<RecentInvoicesBlock />

<!-- Plugin-injected blocks (dynamic, if subscription plugin installed) -->
<component
  v-for="widget in dashboardWidgets"
  :is="widget.component"
  :key="widget.name"
/>
```

**Removed from core Dashboard.vue:**
- Subscription card (primary + multi-subscriptions)
- Subscription history block
- Add-ons block
- Quick actions block

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create plugin skeleton + `index.ts` | — |
| 2 | Move views from `vue/src/views/` to plugin | — |
| 3 | Move checkout components from `vue/src/components/checkout/` to plugin | — |
| 4 | Move stores from `vue/src/stores/` (plans, subscription, checkout) | — |
| 5 | Create dashboard extension components from Dashboard.vue blocks | — |
| 6 | Update all import paths in moved files | — |
| 7 | Add i18n translations to `locales/en.json` | — |
| 8 | Remove moved files from `vue/src/` | — |
| 9 | Remove subscription/plan/addon/checkout routes from `vue/src/router/index.ts` | — |
| 10 | Remove subscription/plan/addon nav items from UserLayout | — |
| 11 | Slim Dashboard.vue — keep only profile + tokens + invoices + plugin widget slots | — |
| 12 | Remove Quick Actions from Dashboard.vue | — |
| 13 | Register in `plugins/plugins.json` + `plugins/config.json` | — |
| 14 | Add `plugins/subscription/` to `.gitignore` | — |
| 15 | Unit tests | Plugin unit tests |
| 16 | `pre-commit-check.sh` — all green | — |

---

## What Gets Removed from fe-user Core

### Views (delete from `vue/src/views/`)
- `Plans.vue`, `PlanDetailView.vue`, `TarifPlanDetail.vue`
- `Subscription.vue`
- `AddOns.vue`, `AddonDetail.vue`, `AddonInfoView.vue`
- `Checkout.vue`

### Components (delete from `vue/src/components/`)
- `checkout/BillingAddressBlock.vue`
- `checkout/EmailBlock.vue`
- `checkout/PaymentMethodsBlock.vue`
- `checkout/TermsCheckbox.vue`

### Stores (delete from `vue/src/stores/`)
- `plans.ts`, `subscription.ts`, `checkout.ts`

### Dashboard.vue (update)
- Remove subscription card, subscription history, add-ons, quick actions
- Add plugin widget slots

### Router (update)
- Remove all `/dashboard/plans/*`, `/dashboard/subscription/*`, `/dashboard/checkout/*`, `/dashboard/add-ons/*` routes

### UserLayout / Nav (update)
- Remove "Plans", "Add-Ons", "Subscription" nav items from core

---

## Note: `checkout` plugin (fe-user)

The existing `plugins/checkout/` plugin in fe-user handles the *public* checkout page. This is subscription-specific and should either:
- Merge into the new `subscription` plugin, or
- Be declared as a dependency of the subscription plugin

Decision: merge into subscription plugin — checkout is meaningless without subscriptions.

---

## Acceptance Criteria

- Plugin renders all plan/subscription/addon/checkout user pages
- Core `vue/src/` has zero subscription/plan/addon/checkout files
- Core Dashboard.vue shows only: profile, token activity, recent invoices
- Dashboard renders subscription blocks only when plugin is enabled
- Quick actions removed from core dashboard
- Nav items appear only when plugin is enabled
- All existing user tests pass
- `pre-commit-check.sh` passes
