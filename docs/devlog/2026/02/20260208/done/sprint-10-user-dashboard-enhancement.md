# Sprint 10 — User Dashboard Enhancement: Subscription History, Add-ons, Token Top-ups

**Priority:** HIGH
**Goal:** Enrich the user dashboard with 4 new data blocks: active subscription (enhanced), subscription history, add-ons (active + expired), and token top-up history.

**Principles:** TDD-first, SOLID (SRP, OCP, LSP, ISP, DIP), DRY, Clean Code, No Overengineering

---

## Overview

### Current State

The user Dashboard.vue displays:
- Profile summary card (name, email, status)
- Subscription card (plan name, status, billing period, next billing, token balance)
- Recent invoices card (last 5)
- Quick actions card (4 links)

### Target State

Add 3 new dashboard cards:
1. **Subscription History** — timeline of subscription events (started, cancelled, plan change, trial)
2. **Add-ons** — active and expired/cancelled add-on subscriptions
3. **Token Top-up History** — token purchase/credit/refund transactions

### Gap Analysis

| Feature | Backend API | Frontend Store | Dashboard UI |
|---------|-------------|----------------|-------------|
| Subscription history | `GET /user/subscriptions` exists (returns all) but lacks plan names | No history in store | Not shown |
| User addon subscriptions | **MISSING** — no user-facing endpoint | No store | Not shown |
| Token transactions | `GET /user/tokens/transactions` exists | No store action | Not shown |

---

## Sprint Breakdown

### Sub-sprint 10a: Backend — User Add-on Subscriptions Endpoint

**Goal:** Add `GET /api/v1/user/addons` returning user's addon subscriptions with addon details.

#### 10a.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/routes/test_user_addons_route.py`

```
Tests to write FIRST:

test_user_addons_returns_all_user_addon_subscriptions
  - Mock addon_subscription_repo.find_by_user() → 2 addon subs
  - GET /user/addons → 200, response has 2 items

test_user_addons_includes_addon_details
  - Addon sub has addon_id → mock addon_repo.find_by_id() returns addon with name, slug
  - Response items have addon.name, addon.slug

test_user_addons_requires_auth
  - GET /user/addons without token → 401

test_user_addons_empty_list
  - No addon subs for user → 200, empty list
```

#### 10a.2 Implementation (GREEN)

**File:** `vbwd-backend/src/routes/user.py` — add endpoint

```python
@user_bp.route("/addons", methods=["GET"])
@require_auth
def get_user_addons():
    """Get current user's add-on subscriptions with addon details."""
    user_id = g.user_id
    container = current_app.container

    addon_sub_repo = container.addon_subscription_repository()
    addon_repo = container.addon_repository()

    addon_subs = addon_sub_repo.find_by_user(
        UUID(user_id) if isinstance(user_id, str) else user_id
    )

    result = []
    for addon_sub in addon_subs:
        data = addon_sub.to_dict()
        if addon_sub.addon_id:
            addon = addon_repo.find_by_id(addon_sub.addon_id)
            if addon:
                data["addon"] = {
                    "name": addon.name,
                    "slug": addon.slug,
                    "description": addon.description,
                    "price": str(addon.price) if addon.price else None,
                    "billing_period": addon.billing_period.value if addon.billing_period else None,
                }
        result.append(data)

    return jsonify({"addon_subscriptions": result}), 200
```

Key: Uses existing `find_by_user()` repository method. Enriches with addon details (SRP — route only transforms data). No new service needed — simple repo query + enrichment.

#### 10a.3 Verify

```bash
cd vbwd-backend && make test-unit
```

---

### Sub-sprint 10b: Backend — Enrich Subscription List with Plan Names

**Goal:** The existing `GET /user/subscriptions` endpoint returns subscriptions but without plan names. Add plan name enrichment.

#### 10b.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/routes/test_subscription_enrichment.py`

```
Tests to write FIRST:

test_list_subscriptions_includes_plan_name
  - Mock subscription with tarif_plan_id → mock plan_repo returns plan
  - Response items have plan.name, plan.billing_period

test_list_subscriptions_handles_missing_plan
  - Subscription has tarif_plan_id but plan_repo returns None
  - Response item has plan: null (no crash)

test_list_subscriptions_sorts_by_created_at_desc
  - 3 subscriptions with different dates
  - Response is newest first
```

#### 10b.2 Implementation (GREEN)

**File:** `vbwd-backend/src/routes/subscriptions.py` — modify `list_subscriptions()`

Add plan enrichment (same pattern as `get_active_subscription()` already does):

```python
@subscriptions_bp.route("", methods=["GET"])
@require_auth
def list_subscriptions():
    subscription_repo = SubscriptionRepository(db.session)
    tarif_plan_repo = TarifPlanRepository(db.session)
    subscription_service = SubscriptionService(subscription_repo=subscription_repo)

    subscriptions = subscription_service.get_user_subscriptions(g.user_id)

    result = []
    for sub in subscriptions:
        data = sub.to_dict()
        if sub.tarif_plan_id:
            plan = tarif_plan_repo.find_by_id(sub.tarif_plan_id)
            if plan:
                data["plan"] = {
                    "id": str(plan.id),
                    "name": plan.name,
                    "slug": plan.slug,
                    "price": float(plan.price) if plan.price else 0,
                    "billing_period": plan.billing_period.value if plan.billing_period else None,
                }
        result.append(data)

    return jsonify({"subscriptions": result}), 200
```

#### 10b.3 Verify

```bash
cd vbwd-backend && make test-unit
```

---

### Sub-sprint 10c: Frontend — Subscription History Store + Card

**Goal:** Add `fetchHistory()` to subscription store and render a subscription history timeline on the dashboard.

#### 10c.1 Unit Tests (RED)

**File:** `vbwd-frontend/user/vue/tests/unit/stores/subscription-history.spec.ts`

```
Tests to write FIRST:

test_fetch_history_populates_state
  - Mock API returns 3 subscriptions (active, cancelled, expired)
  - store.history has 3 items

test_history_sorts_newest_first
  - Mock returns unsorted subscriptions
  - store.history is sorted by started_at desc

test_fetch_history_error_sets_error_state
  - Mock API rejects
  - store.historyError is set

test_history_includes_plan_names
  - Mock returns subscriptions with plan.name
  - store.history items have planName
```

**File:** `vbwd-frontend/user/vue/tests/unit/views/dashboard-subscription-history.spec.ts`

```
Tests to write FIRST:

test_dashboard_renders_subscription_history_card
  - Provide store with 2 history items
  - [data-testid="subscription-history"] visible

test_subscription_history_shows_status_badges
  - History has active + cancelled subscriptions
  - Status badges rendered with correct classes

test_subscription_history_shows_trial_badge_for_trialing
  - History has trialing subscription
  - Trial badge visible

test_subscription_history_empty_state
  - History is empty
  - "No subscription history" message shown
```

#### 10c.2 Implementation (GREEN)

**File:** `vbwd-frontend/user/vue/src/stores/subscription.ts` — extend store

Add to state:
```typescript
history: [] as Subscription[],
historyLoading: false,
historyError: null as string | null,
```

Add action:
```typescript
async fetchHistory() {
  this.historyLoading = true;
  this.historyError = null;
  try {
    const response = await api.get('/user/subscriptions') as { subscriptions: Subscription[] };
    this.history = (response.subscriptions || [])
      .sort((a, b) => new Date(b.started_at || 0).getTime() - new Date(a.started_at || 0).getTime());
  } catch (error) {
    this.historyError = (error as Error).message;
  } finally {
    this.historyLoading = false;
  }
}
```

**File:** `vbwd-frontend/user/vue/src/views/Dashboard.vue` — add Subscription History card

New card after existing subscription card:
```vue
<!-- Subscription History Card -->
<div class="card history-card" data-testid="subscription-history">
  <h3>{{ $t('dashboard.historyCard.title') }}</h3>
  <div v-if="subscriptionHistory.length > 0" class="history-list">
    <div v-for="sub in subscriptionHistory" :key="sub.id"
         class="history-item" data-testid="history-item">
      <div class="history-info">
        <span class="history-plan">{{ sub.plan?.name || 'Unknown Plan' }}</span>
        <span class="history-dates">
          {{ formatDate(sub.started_at) }} — {{ sub.cancelled_at ? formatDate(sub.cancelled_at) : $t('common.present') }}
        </span>
      </div>
      <span class="history-status" :class="sub.status">
        {{ formatStatus(sub.status) }}
      </span>
    </div>
  </div>
  <div v-else class="empty-state">
    <p>{{ $t('dashboard.historyCard.noHistory') }}</p>
  </div>
</div>
```

#### 10c.3 Verify

```bash
cd vbwd-frontend && make test
```

---

### Sub-sprint 10d: Frontend — Add-ons Store + Card

**Goal:** Create add-ons store action and render active/expired add-ons on the dashboard.

#### 10d.1 Unit Tests (RED)

**File:** `vbwd-frontend/user/vue/tests/unit/stores/user-addons.spec.ts`

```
Tests to write FIRST:

test_fetch_user_addons_populates_state
  - Mock API returns 3 addon subscriptions
  - store.addonSubscriptions has 3 items

test_active_addons_getter_filters_active
  - 2 active + 1 cancelled
  - store.activeAddons has 2 items

test_inactive_addons_getter_filters_expired_cancelled
  - 2 active + 1 cancelled + 1 expired
  - store.inactiveAddons has 2 items

test_fetch_error_sets_error
  - Mock API rejects
  - store.addonsError is set
```

**File:** `vbwd-frontend/user/vue/tests/unit/views/dashboard-addons.spec.ts`

```
Tests to write FIRST:

test_dashboard_renders_addons_card
  - Provide store with 2 addon subs
  - [data-testid="user-addons"] visible

test_addons_card_groups_active_and_expired
  - 1 active + 1 cancelled
  - Active section and expired section both rendered

test_addons_card_empty_state
  - No addon subs
  - "No add-ons" message shown

test_addon_shows_name_and_status
  - Addon sub with addon.name
  - Name and status badge rendered
```

#### 10d.2 Implementation (GREEN)

**File:** `vbwd-frontend/user/vue/src/stores/subscription.ts` — extend store (DRY: keep subscription-related data in same store)

Add to state:
```typescript
addonSubscriptions: [] as AddonSubscription[],
addonsLoading: false,
addonsError: null as string | null,
```

Add interface and getters:
```typescript
export interface AddonSubscription {
  id: string;
  addon_id: string;
  status: string;
  starts_at: string | null;
  expires_at: string | null;
  cancelled_at: string | null;
  addon?: { name: string; slug: string; description?: string; price?: string; billing_period?: string };
}
```

Add action:
```typescript
async fetchUserAddons() {
  this.addonsLoading = true;
  this.addonsError = null;
  try {
    const response = await api.get('/user/addons') as { addon_subscriptions: AddonSubscription[] };
    this.addonSubscriptions = response.addon_subscriptions || [];
  } catch (error) {
    this.addonsError = (error as Error).message;
  } finally {
    this.addonsLoading = false;
  }
}
```

Add getters:
```typescript
activeAddons(): AddonSubscription[] {
  return this.addonSubscriptions.filter(a => a.status === 'active');
},
inactiveAddons(): AddonSubscription[] {
  return this.addonSubscriptions.filter(a => a.status !== 'active' && a.status !== 'pending');
},
```

**File:** `vbwd-frontend/user/vue/src/views/Dashboard.vue` — add Add-ons card

```vue
<!-- Add-ons Card -->
<div class="card addons-card" data-testid="user-addons">
  <h3>{{ $t('dashboard.addonsCard.title') }}</h3>
  <div v-if="activeAddons.length > 0 || inactiveAddons.length > 0">
    <div v-if="activeAddons.length > 0" class="addons-section">
      <h4>{{ $t('dashboard.addonsCard.active') }}</h4>
      <div v-for="addon in activeAddons" :key="addon.id" class="addon-item" data-testid="addon-item">
        <span class="addon-name">{{ addon.addon?.name || 'Add-on' }}</span>
        <span class="addon-status active">{{ formatStatus(addon.status) }}</span>
      </div>
    </div>
    <div v-if="inactiveAddons.length > 0" class="addons-section">
      <h4>{{ $t('dashboard.addonsCard.expired') }}</h4>
      <div v-for="addon in inactiveAddons" :key="addon.id" class="addon-item" data-testid="addon-item-inactive">
        <span class="addon-name">{{ addon.addon?.name || 'Add-on' }}</span>
        <span class="addon-status" :class="addon.status">{{ formatStatus(addon.status) }}</span>
      </div>
    </div>
  </div>
  <div v-else class="empty-state">
    <p>{{ $t('dashboard.addonsCard.noAddons') }}</p>
  </div>
  <router-link to="/add-ons" class="card-link">
    {{ $t('dashboard.addonsCard.browseAddons') }} →
  </router-link>
</div>
```

#### 10d.3 Verify

```bash
cd vbwd-frontend && make test
```

---

### Sub-sprint 10e: Frontend — Token Top-up History Card

**Goal:** Fetch token transactions and render a top-up history card on the dashboard.

#### 10e.1 Unit Tests (RED)

**File:** `vbwd-frontend/user/vue/tests/unit/views/dashboard-token-history.spec.ts`

```
Tests to write FIRST:

test_dashboard_renders_token_history_card
  - Provide token transactions (purchase + refund)
  - [data-testid="token-history"] visible

test_token_history_shows_transaction_type_and_amount
  - Purchase of +500 tokens
  - Shows "Purchase" label and "+500"

test_token_history_shows_refund_as_negative
  - Refund of -200 tokens
  - Shows "Refund" label and "-200"

test_token_history_empty_state
  - No transactions
  - "No token activity" message shown

test_token_history_limits_to_recent
  - 20 transactions returned
  - Only shows last 10
```

#### 10e.2 Implementation (GREEN)

**File:** `vbwd-frontend/user/vue/src/views/Dashboard.vue` — extend script + add card

Add to `loadDashboardData()`:
```typescript
const tokenTransactions = ref<TokenTransaction[]>([]);

async function fetchTokenTransactions(): Promise<void> {
  try {
    const response = await api.get('/user/tokens/transactions?limit=10') as { transactions: TokenTransaction[] };
    tokenTransactions.value = response.transactions || [];
  } catch {
    tokenTransactions.value = [];
  }
}
```

Add to `Promise.all`:
```typescript
fetchTokenTransactions(),
```

Template card:
```vue
<!-- Token Top-up History Card -->
<div class="card token-history-card" data-testid="token-history">
  <h3>{{ $t('dashboard.tokenHistoryCard.title') }}</h3>
  <div v-if="tokenTransactions.length > 0" class="token-list">
    <div v-for="tx in tokenTransactions" :key="tx.id" class="token-item" data-testid="token-item">
      <div class="token-info">
        <span class="token-type">{{ formatTransactionType(tx.transaction_type) }}</span>
        <span class="token-date">{{ formatDate(tx.created_at) }}</span>
      </div>
      <span class="token-amount" :class="tx.amount > 0 ? 'credit' : 'debit'">
        {{ tx.amount > 0 ? '+' : '' }}{{ formatNumber(tx.amount) }}
      </span>
    </div>
  </div>
  <div v-else class="empty-state">
    <p>{{ $t('dashboard.tokenHistoryCard.noActivity') }}</p>
  </div>
  <router-link to="/tokens" class="card-link">
    {{ $t('dashboard.tokenHistoryCard.purchaseTokens') }} →
  </router-link>
</div>
```

#### 10e.3 Verify

```bash
cd vbwd-frontend && make test
```

---

### Sub-sprint 10f: i18n — Add New Dashboard Keys (EN + DE)

**Goal:** Add translation keys for all new dashboard cards.

#### 10f.1 Keys to Add

```json
{
  "dashboard": {
    "historyCard": {
      "title": "Subscription History",
      "noHistory": "No subscription history yet."
    },
    "addonsCard": {
      "title": "Add-ons",
      "active": "Active",
      "expired": "Expired / Cancelled",
      "noAddons": "No add-ons yet.",
      "browseAddons": "Browse Add-ons"
    },
    "tokenHistoryCard": {
      "title": "Token Activity",
      "noActivity": "No token activity yet.",
      "purchaseTokens": "Purchase Tokens"
    }
  },
  "common": {
    "present": "Present"
  }
}
```

German translations:
```json
{
  "dashboard": {
    "historyCard": {
      "title": "Abo-Verlauf",
      "noHistory": "Noch kein Abo-Verlauf."
    },
    "addonsCard": {
      "title": "Zusatzoptionen",
      "active": "Aktiv",
      "expired": "Abgelaufen / Gekuendigt",
      "noAddons": "Noch keine Zusatzoptionen.",
      "browseAddons": "Zusatzoptionen durchsuchen"
    },
    "tokenHistoryCard": {
      "title": "Token-Aktivitaet",
      "noActivity": "Noch keine Token-Aktivitaet.",
      "purchaseTokens": "Tokens kaufen"
    }
  },
  "common": {
    "present": "Aktuell"
  }
}
```

Rule: DE keys must match EN structure exactly (previous bug: mismatched keys).

---

### Sub-sprint 10g: Dashboard Layout — Grid Adjustment

**Goal:** Update the dashboard grid from 2-column to accommodate 7 cards.

#### Layout

```
| Profile Summary  | Active Subscription |
| Sub History      | Add-ons             |
| Token History    | Recent Invoices     |
| Quick Actions (full-width)             |
```

The existing CSS grid `grid-template-columns: repeat(2, 1fr)` already handles this. Quick Actions spans full width: `grid-column: 1 / -1`.

---

## Verification (After All Sub-sprints)

### Pre-commit Check

```bash
# Backend tests (Docker)
cd vbwd-backend && make test-unit

# Frontend tests (local)
cd vbwd-frontend && make test

# Lint
cd vbwd-frontend && make lint

# Full pre-commit
cd vbwd-frontend && ./bin/pre-commit-check.sh --user --unit
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --unit
```

### Specific New Tests

```bash
# Backend
cd vbwd-backend && docker compose run --rm test pytest tests/unit/routes/test_user_addons_route.py -v
cd vbwd-backend && docker compose run --rm test pytest tests/unit/routes/test_subscription_enrichment.py -v

# Frontend
cd vbwd-frontend/user && npx vitest run --config vitest.config.js
```

### Manual Smoke Test

```bash
cd vbwd-backend && make up
cd vbwd-frontend && make up
# Navigate to http://localhost:8080/dashboard
# Verify: subscription history card, addons card, token history card
```

---

## File Plan

### New Files

| File | Purpose | Sub-sprint |
|------|---------|------------|
| `tests/unit/routes/test_user_addons_route.py` | Backend addon endpoint tests (4) | 10a |
| `tests/unit/routes/test_subscription_enrichment.py` | Backend subscription enrichment tests (3) | 10b |
| `user/vue/tests/unit/stores/subscription-history.spec.ts` | Frontend history store tests (4) | 10c |
| `user/vue/tests/unit/views/dashboard-subscription-history.spec.ts` | Dashboard history UI tests (4) | 10c |
| `user/vue/tests/unit/stores/user-addons.spec.ts` | Frontend addons store tests (4) | 10d |
| `user/vue/tests/unit/views/dashboard-addons.spec.ts` | Dashboard addons UI tests (4) | 10d |
| `user/vue/tests/unit/views/dashboard-token-history.spec.ts` | Dashboard token history tests (5) | 10e |

### Modified Files

| File | Change | Sub-sprint |
|------|--------|------------|
| `src/routes/user.py` | Add `GET /user/addons` endpoint (~25 lines) | 10a |
| `src/routes/subscriptions.py` | Enrich `list_subscriptions()` with plan names (~15 lines) | 10b |
| `user/vue/src/stores/subscription.ts` | Add `history`, `addonSubscriptions`, `fetchHistory()`, `fetchUserAddons()` | 10c, 10d |
| `user/vue/src/views/Dashboard.vue` | Add 3 new cards (history, addons, tokens) + grid adjustment | 10c, 10d, 10e, 10g |
| `user/vue/src/i18n/locales/en.json` | Add ~12 new keys | 10f |
| `user/vue/src/i18n/locales/de.json` | Add ~12 new keys (matching EN structure) | 10f |

---

## TDD Execution Order

| Step | Type | Sub-sprint | Description | Status |
|------|------|------------|-------------|--------|
| 1 | Unit (RED) | 10a | Write backend addon endpoint tests — 4 tests fail | [ ] |
| 2 | Code (GREEN) | 10a | Add `GET /user/addons` route — tests pass | [ ] |
| 3 | Verify | 10a | `make test-unit` — all backend tests pass | [ ] |
| 4 | Unit (RED) | 10b | Write subscription enrichment tests — 3 tests fail | [ ] |
| 5 | Code (GREEN) | 10b | Enrich `list_subscriptions()` — tests pass | [ ] |
| 6 | Verify | 10b | `make test-unit` — all backend tests pass | [ ] |
| 7 | Unit (RED) | 10c | Write history store + UI tests — 8 tests fail | [ ] |
| 8 | Code (GREEN) | 10c | Add `fetchHistory()` + history card — tests pass | [ ] |
| 9 | Unit (RED) | 10d | Write addons store + UI tests — 8 tests fail | [ ] |
| 10 | Code (GREEN) | 10d | Add `fetchUserAddons()` + addons card — tests pass | [ ] |
| 11 | Unit (RED) | 10e | Write token history tests — 5 tests fail | [ ] |
| 12 | Code (GREEN) | 10e | Add token history card — tests pass | [ ] |
| 13 | i18n | 10f | Add EN + DE keys (verify key count matches) | [ ] |
| 14 | CSS | 10g | Adjust grid layout for 7 cards | [ ] |
| 15 | Verify | ALL | `make test` (frontend) + `make test-unit` (backend) — zero regressions | [ ] |
| 16 | Verify | ALL | Pre-commit check passes | [ ] |
| 17 | Verify | ALL | Manual smoke test — all cards render | [ ] |

---

## Definition of Done

- [ ] `GET /api/v1/user/addons` returns addon subscriptions with addon details
- [ ] `GET /api/v1/user/subscriptions` returns subscriptions enriched with plan names
- [ ] Dashboard shows subscription history card with status badges (active/cancelled/trialing/expired)
- [ ] Dashboard shows add-ons card with active and expired/cancelled sections
- [ ] Dashboard shows token activity card with top-up, usage, refund entries
- [ ] All i18n keys added in EN and DE (matching key structure)
- [ ] 7 new backend tests pass
- [ ] ~25 new frontend tests pass
- [ ] All existing tests pass (no regressions)
- [ ] Pre-commit check passes for both user and admin apps

---

## Principles Applied

| Principle | Application |
|-----------|-------------|
| **TDD** | Tests written first (RED), then implementation (GREEN), at every sub-sprint |
| **SRP** | Each sub-sprint has one responsibility. Backend route only transforms data. Store only manages state. Component only renders. |
| **OCP** | Dashboard grid is open to new cards without modifying existing ones |
| **LSP** | `AddonSubscription` interface compatible with existing subscription patterns |
| **ISP** | Store split: subscription history vs addon subscriptions — consumers only depend on what they need |
| **DIP** | Frontend uses store abstraction (not direct API calls in components). Backend uses repository pattern. |
| **DRY** | `formatStatus()`, `formatDate()`, `formatPrice()` reused across all cards. Subscription store extended (not duplicated). |
| **Clean Code** | Descriptive test names, small functions, clear data-testid attributes for testing |
| **No Overengineering** | No new services for simple repo queries. No pagination on dashboard cards (limit built into API call). No websocket updates. |
