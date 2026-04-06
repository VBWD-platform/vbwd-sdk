# Sprint 11 — Tarif Plan Detail Page + GHRM Software & GitHub Access Tabs

**Status:** Pending approval
**Scope:** fe-user core + GHRM plugin (fe-user + backend)

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before or alongside implementation. No step is done without passing tests. |
| **SOLID** | Single responsibility per component/service. Open for extension (tab registry), closed for modification (no GHRM imports in core files). |
| **DI** | Backend: services receive repositories via constructor, no `db.session` inside service methods. Frontend: composables and stores inject dependencies. |
| **DRY** | Reuse `GhrmMarkdownRenderer`, `GhrmVersionsTable`, `GhrmGithubConnectButton`. No duplicated plan-fetch logic. |
| **Liskov** | `GhrmPlanSoftwareTab` and `GhrmPlanGithubAccessTab` honour the `PlanDetailTab` interface contract (accept `planSlug` prop, render independently). |
| **Clean code** | No `console.log`, no `as any`, no bare `except: pass`. Explicit types on all props, emits, and store actions. |
| **No over-engineering** | Tab registry is a plain `ref<PlanDetailTab[]>`, not a class hierarchy. Minimum complexity for the current task. |
| **Drop deprecated** | Use `marked.parse()` not `marked()`. Use `db.session.get()` not `Model.query` on backend. |
| **Theme-switcher compatible** | All new views and components must use `--vbwd-*` CSS variables for colours, backgrounds, and borders. No hardcoded hex colours. See table below. |

### CSS Variables (theme-switcher contract)

All new `.vue` files must use these variables — never hardcode colours.

| Variable | Purpose | Fallback |
|----------|---------|---------|
| `--vbwd-page-bg` | Page background | `#f5f5f5` |
| `--vbwd-card-bg` | Card / panel background | `#ffffff` |
| `--vbwd-card-shadow` | Card box-shadow | `0 2px 5px rgba(0,0,0,.05)` |
| `--vbwd-text-heading` | h1, h2, h3 | `#2c3e50` |
| `--vbwd-text-body` | Body text | `#333333` |
| `--vbwd-text-muted` | Labels, secondary text | `#666666` |
| `--vbwd-color-primary` | Links, active tabs, buttons | `#3498db` |
| `--vbwd-color-primary-hover` | Hover state | `#2980b9` |
| `--vbwd-color-success` | Success / active badge | `#27ae60` |
| `--vbwd-color-danger` | Error / cancel | `#e74c3c` |
| `--vbwd-color-warning` | Warning messages | `#f39c12` |
| `--vbwd-border-color` | Table borders, dividers | `#dddddd` |
| `--vbwd-border-light` | Subtle separators | `#eeeeee` |

**Wrapper class pattern** — root `<div>` of `TarifPlanDetail.vue` must be:
```html
<div class="tarif-plan-detail">
```

Scoped styles reference the same pattern used on `http://localhost:8081/admin/plans/:id/edit` (`plan-form-view`):
```css
.tarif-plan-detail {
  background: var(--vbwd-page-bg, #f5f5f5);
  padding: 20px;
  border-radius: 8px;
}
.tarif-plan-detail .card {
  background: var(--vbwd-card-bg, #fff);
  box-shadow: var(--vbwd-card-shadow, 0 2px 5px rgba(0,0,0,.05));
  border-radius: 8px;
  padding: 20px;
}
```

All GHRM tab components (`GhrmPlanSoftwareTab`, `GhrmPlanGithubAccessTab`) follow the same convention — no hardcoded colours.

---

## Background

The subscription page (`/dashboard/subscription`) shows active subscriptions but clicking a row does nothing. Each subscription is linked to a tariff plan (`sub.tarif_plan_id`). The GHRM plugin stores packages with a 1-to-1 FK to `tarif_plan` (`ghrm_software_package.tariff_plan_id`). The backend already generates `git clone` / `npm` / `pip` / `composer` install commands in `get_install_instructions()` using the user's GitHub deploy token.

**Goal:** clicking a subscription row always opens the plan detail page. The core page shows a "Plan Description" tab with plan fields regardless of GHRM. If the plan has a GHRM package attached, the plugin adds two extra tabs: "Software" (full 5-sub-tab content) and "GitHub Access" (clone commands or status message).

---

## Architecture Decision — Tab Extension Registry

The core plan detail page must remain plugin-agnostic. The GHRM plugin registers its own tabs at boot time via a lightweight `planDetailTabRegistry`:

```
vue/src/utils/planDetailTabRegistry.ts   ← new singleton, owned by core
```

The plan detail page reads `planDetailTabRegistry.tabs` and renders them after the core info. The GHRM plugin calls `planDetailTabRegistry.register(...)` inside its `install()` hook. No imports from GHRM in core files.

---

## Steps

### Step 1 — Subscription row: add click navigation

**File:** `vue/src/views/Subscription.vue`

Add `@click` to the active subscription `<tr>`:
```html
<tr
  v-for="sub in activeSubscriptions"
  :key="sub.id"
  data-testid="active-sub-row"
  style="cursor: pointer"
  @click="goToPlan(sub)"
>
  <td @click.stop>  <!-- protect cancel button from row click -->
    ...cancel button...
  </td>
```

Add handler (requires `useRouter` import):
```ts
function goToPlan(sub: Subscription) {
  router.push(`/dashboard/tarif/${sub.tarif_plan_id}`)
}
```

The `to_dict()` of `Subscription` already returns `tarif_plan_id` (see `src/models/subscription.py:134`).

---

### Step 2 — Core route `/dashboard/tarif/:planSlug`

**File:** `vue/src/router/index.ts`

```ts
{
  path: '/dashboard/tarif/:planSlug',
  name: 'tarif-plan-detail',
  component: () => import('../views/TarifPlanDetail.vue'),
  meta: { requiresAuth: true },
},
```

**Step 1 updated accordingly** — `goToPlan()` navigates by plan slug, not UUID:
```ts
function goToPlan(sub: Subscription) {
  router.push(`/dashboard/tarif/${sub.plan?.slug}`)
}
```
The subscription API response already includes `sub.plan.slug` via the eager-loaded `plan` relation.

---

### Step 3 — `TarifPlanDetail.vue` (core view)

**File:** `vue/src/views/TarifPlanDetail.vue` (new)

Fetches plan from existing endpoint `GET /api/v1/tarif-plans/:planId` (already used in `PlanDetailView.vue`).

Route param: `planSlug`. Fetches from `GET /api/v1/tarif-plans/:planSlug`.

Tab layout — always renders at least one tab:

| Tab | Owner | Content |
|-----|-------|---------|
| Plan Description | core | Name, Price, Billing Period, Trial Days, Category, Description, Features table |
| Software | GHRM plugin | readme, screenshots, changelog, docs, versions (5 sub-tabs, same as package detail) |
| GitHub Access | GHRM plugin | connection status + clone commands or inactive message |

The core page always shows "Plan Description" as the first tab. Plugin tabs are appended from `planDetailTabRegistry`. Each registered tab receives `:plan-slug="planSlug"` as a prop.

Includes a "← Back to Subscription" link to `/dashboard/subscription`.

**Uses `pf-tabs` CSS class pattern** — same classes as `http://localhost:8081/admin/plans/:id/edit` so the tab styling is consistent across admin and user dashboards, and fully compatible with `theme-switcher` CSS variables (no hardcoded colours).

```vue
<template>
  <div class="tarif-plan-detail">
    <router-link to="/dashboard/subscription" class="back-link">
      &larr; {{ $t('tarifPlanDetail.backLink') }}
    </router-link>

    <div v-if="loading" class="loading-state" data-testid="plan-loading">...</div>
    <div v-else-if="error" class="error-state" data-testid="plan-error">{{ error }}</div>

    <template v-else-if="plan">
      <h1 class="page-title" data-testid="plan-name">{{ plan.name }}</h1>

      <div class="pf-tabs">
        <div class="pf-tabs__bar">
          <!-- Built-in "Plan Description" tab — always present -->
          <button
            type="button"
            class="pf-tabs__tab"
            :class="{ 'pf-tabs__tab--active': activeTab === 'plan-description' }"
            data-testid="tab-plan-description"
            @click="activeTab = 'plan-description'"
          >{{ $t('tarifPlanDetail.tabPlanDescription') }}</button>

          <!-- Plugin-registered tabs -->
          <button
            v-for="tab in tabRegistry.tabs.value"
            :key="tab.id"
            type="button"
            class="pf-tabs__tab"
            :class="{ 'pf-tabs__tab--active': activeTab === tab.id }"
            :data-testid="`tab-${tab.id}`"
            @click="activeTab = tab.id"
          >{{ tab.label }}</button>
        </div>

        <div class="pf-tabs__panel">
          <!-- Plan Description content -->
          <template v-if="activeTab === 'plan-description'">
            <div class="plan-meta-grid" data-testid="plan-meta">
              <div class="meta-item">
                <span class="meta-label">{{ $t('tarifPlanDetail.price') }}</span>
                <span class="meta-value" data-testid="plan-price">{{ formatPrice(plan) }}</span>
              </div>
              <div class="meta-item">
                <span class="meta-label">{{ $t('tarifPlanDetail.billingPeriod') }}</span>
                <span class="meta-value" data-testid="plan-billing-period">{{ plan.billing_period || '—' }}</span>
              </div>
              <div v-if="plan.trial_days" class="meta-item">
                <span class="meta-label">{{ $t('tarifPlanDetail.trialDays') }}</span>
                <span class="meta-value" data-testid="plan-trial-days">{{ plan.trial_days }}</span>
              </div>
              <div v-if="plan.category" class="meta-item">
                <span class="meta-label">{{ $t('tarifPlanDetail.category') }}</span>
                <span class="meta-value" data-testid="plan-category">{{ plan.category }}</span>
              </div>
            </div>
            <p v-if="plan.description" class="plan-description" data-testid="plan-description">
              {{ plan.description }}
            </p>
            <table v-if="plan.features?.length" class="plan-features-table" data-testid="plan-features">
              <tbody>
                <tr v-for="f in plan.features" :key="f">
                  <td class="feature-check">✓</td>
                  <td>{{ f }}</td>
                </tr>
              </tbody>
            </table>
          </template>

          <!-- Plugin tab content -->
          <component
            :is="activeTabDef?.component"
            v-else-if="activeTabDef"
            :plan-slug="planSlug"
          />
        </div>
      </div>
    </template>
  </div>
</template>
```

Scoped CSS uses `pf-tabs` classes with `--vbwd-*` variables — **no hardcoded hex colours**:
```css
.tarif-plan-detail {
  background: var(--vbwd-page-bg, #f5f5f5);
  max-width: 900px;
  margin: 0 auto;
  padding: 20px;
}
.pf-tabs { border: 1px solid var(--vbwd-border-color, #ddd); border-radius: 8px; overflow: hidden; }
.pf-tabs__bar { display: flex; background: var(--vbwd-card-bg, #f8f9fa); border-bottom: 1px solid var(--vbwd-border-color, #ddd); overflow-x: auto; }
.pf-tabs__tab { padding: 12px 20px; background: none; border: none; border-right: 1px solid var(--vbwd-border-light, #eee); cursor: pointer; font-size: 14px; color: var(--vbwd-text-body, #555); white-space: nowrap; }
.pf-tabs__tab:hover { background: var(--vbwd-border-light, #f0f0f0); }
.pf-tabs__tab--active { background: var(--vbwd-card-bg, #fff); color: var(--vbwd-text-heading, #2c3e50); font-weight: 600; border-bottom: 2px solid var(--vbwd-color-primary, #3498db); margin-bottom: -1px; }
.pf-tabs__panel { padding: 24px; background: var(--vbwd-card-bg, #fff); min-height: 200px; }
.meta-label { color: var(--vbwd-text-muted, #666); font-size: .85rem; }
.meta-value { color: var(--vbwd-text-heading, #2c3e50); font-weight: 500; }
.feature-check { color: var(--vbwd-color-success, #27ae60); padding-right: 8px; }
```

---

### Step 4 — `planDetailTabRegistry.ts`

**File:** `vue/src/utils/planDetailTabRegistry.ts` (new)

```ts
import { ref } from 'vue'
import type { Component } from 'vue'

export interface PlanDetailTab {
  id: string
  label: string
  component: Component
}

const tabs = ref<PlanDetailTab[]>([])

export const planDetailTabRegistry = {
  register(tab: PlanDetailTab) {
    if (!tabs.value.find(t => t.id === tab.id)) {
      tabs.value.push(tab)
    }
  },
  tabs,
}
```

---

### Step 5 — Backend: `GET /api/v1/ghrm/packages/by-plan/<plan_id>`

**File:** `vbwd-backend/plugins/ghrm/src/routes.py`

New endpoint — looks up `GhrmSoftwarePackage` by `tariff_plan_id`:

```python
@ghrm_bp.route("/packages/by-plan/<plan_id>", methods=["GET"])
def get_package_by_plan(plan_id: str) -> Response:
    svc = _software_package_service()
    pkg = svc.get_by_tariff_plan_id(plan_id)
    if not pkg:
        return jsonify({"error": "No package for this plan"}), 404
    return jsonify(pkg.to_dict())
```

**File:** `vbwd-backend/plugins/ghrm/src/services/software_package_service.py`

Add `get_by_tariff_plan_id(plan_id: str)`:
```python
def get_by_tariff_plan_id(self, plan_id: str) -> Optional[GhrmSoftwarePackage]:
    return self.repo.find_by_tariff_plan_id(plan_id)
```

**File:** `vbwd-backend/plugins/ghrm/src/repositories/ghrm_software_package_repository.py`

Add method:
```python
def find_by_tariff_plan_id(self, plan_id: str) -> Optional[GhrmSoftwarePackage]:
    return GhrmSoftwarePackage.query.filter_by(tariff_plan_id=plan_id).first()
```

---

### Step 6 — Frontend: `ghrmApi.ts` — add `getPackageByPlan`

**File:** `plugins/ghrm/src/api/ghrmApi.ts`

```ts
getPackageByPlan(planId: string): Promise<GhrmPackage> {
  return get(`${API}/packages/by-plan/${planId}`)
},
```

---

### Step 7 — GHRM "Software" tab: `GhrmPlanSoftwareTab.vue`

**File:** `plugins/ghrm/src/components/GhrmPlanSoftwareTab.vue` (new)

Props: `planId: string`

Lifecycle:
- `onMounted`: calls `ghrmApi.getPackageByPlan(planId)` to find the package slug
- Then calls store's `fetchPackage(slug)`, `fetchRelated(slug)`, `fetchVersions(slug)`
- On 404: renders "No software attached to this plan"

Renders the same tabs as `GhrmPackageDetail.vue` but without the page header (no icon, badges, CTA — those are irrelevant on the dashboard):
- Overview (readme)
- Screenshots
- Changelog
- Documentation
- Versions

Reuses existing components: `GhrmMarkdownRenderer`, `GhrmVersionsTable`.

---

### Step 8 — GHRM "GitHub Access" tab: `GhrmPlanGithubAccessTab.vue`

**File:** `plugins/ghrm/src/components/GhrmPlanGithubAccessTab.vue` (new)

Props: `planId: string`

Lifecycle:
1. `onMounted`: resolve package slug via `ghrmApi.getPackageByPlan(planId)` (or reuse data from step 7 if already loaded — use the same store call)
2. Call `store.fetchAccessStatus()`
3. If connected + has slug: call `store.fetchInstallInstructions(slug)` — the store already has `installInstructions` ref and `fetchInstallInstructions()` action

**Display logic:**

```
┌─────────────────────────────────────────────────────┐
│ GitHub Connection                                    │
│  [GhrmGithubConnectButton]  ← reuse existing comp   │
│                                                      │
│ Access Status                                        │
│  ┌─────────────────────────────────────────────────┐│
│  │ ✅ Connected as @username                        ││
│  │                                                  ││
│  │ ACTIVE (or price = 0):                           ││
│  │   git clone ...                                  ││
│  │   npm install ...                                ││
│  │   pip install ...                                ││
│  │   composer require ...                           ││
│  │                                                  ││
│  │ PENDING / FAILED / CANCELLED / EXPIRED:          ││
│  │   ⚠ You cannot clone or update your local code  ││
│  │     with a pending or inactive subscription.     ││
│  │     Renew your plan to restore access.           ││
│  └─────────────────────────────────────────────────┘│
│                                                      │
│  Not connected:                                      │
│   Connect GitHub to get clone instructions.         │
└─────────────────────────────────────────────────────┘
```

**Access status logic:**
```ts
// "can access" = connected + (access_status === 'active' OR plan.price === 0)
const canAccess = computed(() =>
  accessStatus.value?.connected &&
  (accessStatus.value.access_status === 'active' || planIsFree.value)
)
```

`planIsFree` is determined by checking `plan.price === 0` — passed in from `TarifPlanDetail.vue` as a prop or fetched again.

Install instructions block shows each command in a `<pre><code>` block with a copy button.

---

### Step 9 — GHRM plugin: register tabs in `install()`

**File:** `plugins/ghrm/index.ts` (or wherever `ghrmPlugin.install()` is defined)

```ts
import { planDetailTabRegistry } from '@/utils/planDetailTabRegistry'
import GhrmPlanSoftwareTab from './src/components/GhrmPlanSoftwareTab.vue'
import GhrmPlanGithubAccessTab from './src/components/GhrmPlanGithubAccessTab.vue'

install(sdk: IPlatformSDK) {
  // existing routes...

  planDetailTabRegistry.register({
    id: 'ghrm-software',
    label: 'Software',
    component: GhrmPlanSoftwareTab,
  })
  planDetailTabRegistry.register({
    id: 'ghrm-github-access',
    label: 'GitHub Access',
    component: GhrmPlanGithubAccessTab,
  })
}
```

---

### Step 10 — fe-admin: Invoice line item row click → plan edit page

**File:** `vbwd-fe-admin/vue/src/views/InvoiceDetails.vue`

**Bug:** `itemLink()` compares `item.type` (which is `'SUBSCRIPTION'` uppercase from the API) against lowercase `case 'subscription'` — so the switch never matches and `itemLink` always returns `null`, meaning no link or row click is ever rendered.

**Fix 1 — normalise type in `itemLink`:**
```ts
function itemLink(item: { type?: string; item_id?: string }): string | null {
  if (!item.item_id) return null;
  switch (item.type?.toUpperCase()) {
    case 'SUBSCRIPTION':
      return `/admin/plans/${item.item_id}/edit`;
    case 'TOKEN_BUNDLE':
      return `/admin/settings/token-bundles/${item.item_id}`;
    case 'ADD_ON':
      return '/admin/add-ons';
    default:
      return null;
  }
}
```

**Fix 2 — make the entire `<tr>` clickable, not just the description text:**

```html
<tr
  v-for="item in invoice.line_items"
  :key="item.id || item.description"
  :class="{ 'clickable-row': !!itemLink(item) }"
  :style="itemLink(item) ? 'cursor: pointer' : ''"
  @click="itemLink(item) && router.push(itemLink(item)!)"
>
  <td>
    <span class="type-badge" :class="item.type?.toLowerCase()">
      {{ itemTypeLabel(item.type) }}
    </span>
  </td>
  <td>{{ item.description }}</td>   <!-- no router-link needed — whole row is clickable -->
  <td>{{ item.quantity || 1 }}</td>
  <td>{{ formatAmount(item.unit_price || item.amount, invoice.currency) }}</td>
  <td>{{ formatAmount(item.amount, invoice.currency) }}</td>
</tr>
```

Remove the `<router-link v-if="itemLink(item)">` / `<span v-else>` toggle from the description cell — it's replaced by the row-level click.

Requires `useRouter` import (already present if `router.push` is used elsewhere in the file; if not, add `const router = useRouter()`).

#### Unit test
**File:** `vbwd-fe-admin/vue/tests/unit/views/invoice-details-line-items.spec.ts` (new)

- `SUBSCRIPTION` item with `item_id` → `itemLink` returns `/admin/plans/:id/edit`
- `TOKEN_BUNDLE` item with `item_id` → returns token-bundle path
- `ADD_ON` item → returns `/admin/add-ons`
- `item_id` absent → returns `null`
- clicking `<tr>` for SUBSCRIPTION item calls `router.push` with correct plan path
- clicking `<tr>` for item without link does not call `router.push`

---

### Step 11 — Tests

#### Backend (pytest unit)
**File:** `plugins/ghrm/tests/unit/test_package_by_plan.py`

- `test_get_by_tariff_plan_id_found` — mock repo, service returns package
- `test_get_by_tariff_plan_id_not_found` — returns None → route returns 404

#### Frontend unit (Vitest)
**File:** `vue/tests/unit/views/tarif-plan-detail.spec.ts`

- Renders plan name, price, billing period
- Renders features list
- Renders registered tabs when `planDetailTabRegistry.tabs` is non-empty
- Does not render tab area when no tabs registered

**File:** `vue/tests/unit/plugins/ghrm-plan-software-tab.spec.ts`

- Calls `getPackageByPlan` on mount
- Renders "no software" when 404
- Renders overview tab by default when package found

**File:** `vue/tests/unit/plugins/ghrm-plan-github-access-tab.spec.ts`

- Not connected: shows connect button, no install commands
- Connected + active: shows install commands block
- Connected + pending: shows inactive subscription message
- Connected + price=0: shows install commands even without paid subscription

---

## Checklist

### Backend
- [ ] Step 5a: `find_by_tariff_plan_id()` in repository
- [ ] Step 5b: `get_by_tariff_plan_id()` in service
- [ ] Step 5c: `GET /packages/by-plan/<plan_id>` route
- [ ] Step 10a: backend unit tests

### Core (fe-user)
- [ ] Step 1: Subscription row click → `goToPlan()`
- [ ] Step 2: Router entry for `/dashboard/tarif/:planSlug`
- [ ] Step 3: `TarifPlanDetail.vue` (`pf-tabs` pattern, `--vbwd-*` CSS vars)
- [ ] Step 4: `planDetailTabRegistry.ts`
- [ ] Step 11a: `tarif-plan-detail.spec.ts`

### GHRM plugin (fe-user)
- [ ] Step 6: `getPackageByPlan()` in `ghrmApi.ts`
- [ ] Step 7: `GhrmPlanSoftwareTab.vue`
- [ ] Step 8: `GhrmPlanGithubAccessTab.vue`
- [ ] Step 9: tab registration in `ghrmPlugin.install()`
- [ ] Step 11b: `ghrm-plan-software-tab.spec.ts` + `ghrm-plan-github-access-tab.spec.ts`

### Core (fe-admin)
- [ ] Step 10a: fix `itemLink` type case bug (`SUBSCRIPTION` vs `subscription`)
- [ ] Step 10b: make invoice line item `<tr>` clickable
- [ ] Step 11c: `invoice-details-line-items.spec.ts`

---

## Notes

- **Store deduplication**: `GhrmPlanSoftwareTab` and `GhrmPlanGithubAccessTab` both need the package slug. The Software tab fetches it first — the GitHub Access tab can wait for the store's `currentPackage` ref or pass the slug as a prop through `TarifPlanDetail.vue` once resolved.
- **Plan price = 0 means free**: the backend `TarifPlan.price` is a Decimal; `plan.price == 0` (or `display_price == 0`) should grant access regardless of subscription status.
- **`store.fetchInstallInstructions(slug)` already exists** in `useGhrmStore.ts` — no new store action needed.
- **No backend changes for subscription to_dict**: `tarif_plan_id` is already serialized in `Subscription.to_dict()` (line 134 of `src/models/subscription.py`).
- **`@click.stop` on actions-cell**: the cancel button must not trigger row navigation — use `@click.stop` on the `<td class="actions-cell">` like the AddOns fix from Sprint 06.
- **Invoice line item bug root cause**: `InvoiceDetails.vue:itemLink()` uses `case 'subscription'` (lowercase) but the API returns `item.type = 'SUBSCRIPTION'` (uppercase). Fix: `item.type?.toUpperCase()` in the switch. The `<router-link>` inside description `<td>` is also replaced by row-level `@click` so the full row is the click target, consistent with the subscription row and addon row patterns.

---

## Pre-commit Checks

Run after every step before marking it done.

### vbwd-backend (`vbwd-backend/`)
```bash
# Lint only (Black + Flake8 + Mypy)
./bin/pre-commit-check.sh --lint

# Lint + unit tests
./bin/pre-commit-check.sh --unit

# Lint + integration tests (requires running PostgreSQL)
./bin/pre-commit-check.sh --integration

# Full (lint + unit + integration) — required before sprint sign-off
./bin/pre-commit-check.sh --full
```

### fe-user (`vbwd-fe-user/`)
```bash
# Style checks (ESLint + TypeScript)
./bin/pre-commit-check.sh --style

# Style + unit tests  (runs vue/tests/unit/ — includes vue/tests/unit/plugins/)
./bin/pre-commit-check.sh --unit

# Full — required before sprint sign-off
./bin/pre-commit-check.sh --all
```

### fe-admin (`vbwd-fe-admin/`)
```bash
# Style checks (ESLint + TypeScript)
./bin/pre-commit-check.sh --style

# Style + unit tests  (runs vue/tests/unit/ plugins/)
./bin/pre-commit-check.sh --unit

# Full — required before sprint sign-off
./bin/pre-commit-check.sh --all
```

All checks must pass before the sprint is considered complete.
