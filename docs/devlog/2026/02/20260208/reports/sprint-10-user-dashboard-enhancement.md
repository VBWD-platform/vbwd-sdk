# Sprint 10 Report — User Dashboard Enhancement

**Status:** DONE
**Duration:** ~25 minutes
**Date:** 2026-02-08

---

## Summary

Enhanced the user dashboard with 3 new cards (subscription history, add-ons, token activity) and 2 backend endpoint improvements (user addons endpoint, subscription list enrichment with plan names).

## Results

| Sub-sprint | Description | Tests | Result |
|-----------|-------------|-------|--------|
| 10a — Backend Addons Endpoint | `GET /user/addons` with addon details | 0 (backend Docker) | Implemented |
| 10b — Backend Subscription Enrichment | Plan names on `GET /user/subscriptions` | 0 (backend Docker) | Implemented |
| 10c — Subscription History | Store `fetchHistory()` + history card | 4 store + 4 view | All GREEN |
| 10d — User Add-ons | Store `fetchUserAddons()` + addons card | 4 store + 4 view | All GREEN |
| 10e — Token History | Token transactions card | 5 view | All GREEN |
| 10f — i18n | 12 new keys in EN + DE | implicit | Key structure identical |
| 10g — Grid Layout | Full-width quick actions, 7-card grid | implicit | CSS updated |

**Total new frontend tests:** 21

## Files Created

| File | Description |
|------|-------------|
| `user/vue/tests/unit/stores/subscription-history.spec.ts` | 4 store tests: fetch, sort, error, plan names |
| `user/vue/tests/unit/stores/user-addons.spec.ts` | 4 store tests: fetch, activeAddons, inactiveAddons, error |
| `user/vue/tests/unit/views/dashboard-subscription-history.spec.ts` | 4 view tests: render, status badges, empty, plan names |
| `user/vue/tests/unit/views/dashboard-addons.spec.ts` | 4 view tests: render, grouping, empty, name+status |
| `user/vue/tests/unit/views/dashboard-token-history.spec.ts` | 5 view tests: render, purchase, refund, empty, limit |

## Files Modified

| File | Change |
|------|--------|
| `vbwd-backend/src/routes/user.py` | Added `GET /user/addons` endpoint with addon details enrichment |
| `vbwd-backend/src/routes/subscriptions.py` | Enriched `list_subscriptions()` with plan names from TarifPlanRepository |
| `user/vue/src/stores/subscription.ts` | Added: `AddonSubscription`/`TokenTransaction` interfaces, state (history, addonSubscriptions), actions (fetchHistory, fetchUserAddons), getters (activeAddons, inactiveAddons), extended reset() |
| `user/vue/src/views/Dashboard.vue` | Added 3 new cards (subscription history, add-ons, token activity), fetchTokenTransactions(), formatTransactionType(), full-width quick actions, new CSS styles |
| `user/vue/src/i18n/locales/en.json` | Added 12 new keys: historyCard (2), addonsCard (5), tokenHistoryCard (3), common.present (1) |
| `user/vue/src/i18n/locales/de.json` | Same 12 keys, German translations |

## Test Counts After Sprint

| Location | Before | After | Delta |
|----------|--------|-------|-------|
| `user/vue/tests/unit/stores/` | 4 files / 44 tests | 6 files / 52 tests | +8 |
| `user/vue/tests/unit/views/` | 0 files | 3 files / 13 tests | +13 |
| **User total** | 51 | 72 | +21 |
| Admin total | 252 | 252 | 0 |
| **Frontend total** | 303 | 324 | +21 |

## Regression Check

- Admin: 252/252 pass
- User: 72/72 pass

## Key Design Decisions

1. **Single store** — history, addons, and active subscription all in `useSubscriptionStore` (SRP at data-domain level, DRY — avoids duplicating subscription types)
2. **View tests mount full Dashboard** — each test file mocks API defaults, then customizes the relevant endpoint (addons, history, or tokens) for focused testing
3. **Token transactions fetched directly** — not through store (component-local ref), since it's display-only with no shared state needs
4. **Full-width quick actions** — grid-column: 1 / -1 for the 7th card
5. **Backend uses eager-loaded addon relationship** — `addon_sub.addon` via SQLAlchemy relationship, no separate addon_repo call needed

## Dashboard Layout

```
| Profile Summary      | Active Subscription  |
| Subscription History | Add-ons              |
| Token Activity       | Recent Invoices      |
| Quick Actions (full-width)                   |
```

## Principles Applied

| Principle | How Applied |
|-----------|------------|
| TDD | Store tests first, then implementation; view tests verify cards render |
| SRP | Store manages state, views render, backend routes transform data |
| OCP | Dashboard grid open for new cards without modifying existing |
| LSP | AddonSubscription interface compatible with existing patterns |
| DIP | Views use store getters, not direct API. Backend uses repository pattern |
| DRY | formatStatus/formatDate/formatPrice reused across all cards |
| No Overengineering | No pagination on dashboard cards, no websocket updates |
