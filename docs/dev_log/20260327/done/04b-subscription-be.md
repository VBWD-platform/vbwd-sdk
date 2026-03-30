# Sprint 04b — Subscription Backend Plugin

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Create `plugins/subscription/` backend plugin that owns all subscription, tarif plan, add-on, and category logic. Register `SubscriptionLineItemHandler` to handle `SUBSCRIPTION` and `ADD_ON` line items. Core's `CoreLineItemHandler` drops to `TOKEN_BUNDLE` only.

---

## Plugin Structure

```
plugins/subscription/
├── __init__.py                          SubscriptionPlugin(BasePlugin)
├── admin-config.json                    Admin UI config tabs
├── populate_db.py                       Demo plans, categories, subscriptions
├── subscription/
│   ├── models/
│   │   ├── subscription.py              from vbwd/models/subscription.py
│   │   ├── tarif_plan.py                from vbwd/models/tarif_plan.py
│   │   ├── addon.py                     from vbwd/models/addon.py
│   │   ├── addon_subscription.py        from vbwd/models/addon_subscription.py
│   │   └── tarif_plan_category.py       from vbwd/models/tarif_plan_category.py
│   ├── repositories/
│   │   ├── subscription_repository.py
│   │   ├── tarif_plan_repository.py
│   │   ├── addon_repository.py
│   │   ├── addon_subscription_repository.py
│   │   └── tarif_plan_category_repository.py
│   ├── services/
│   │   ├── subscription_service.py
│   │   ├── tarif_plan_service.py
│   │   ├── tarif_plan_category_service.py
│   │   └── checkout_service.py          extracted from checkout_handler
│   ├── handlers/
│   │   ├── line_item_handler.py         SubscriptionLineItemHandler (SUBSCRIPTION + ADD_ON)
│   │   ├── checkout_handler.py          from vbwd/handlers/checkout_handler.py
│   │   ├── subscription_handlers.py     email event handlers
│   │   └── cancel_handler.py            from vbwd/handlers/subscription_cancel_handler.py
│   ├── events.py                        subscription_events + checkout_events
│   ├── scheduler.py                     expiration, trial, dunning
│   └── routes.py                        all user + admin routes (single blueprint)
└── tests/
    ├── conftest.py
    ├── unit/
    │   ├── test_subscription_service.py
    │   ├── test_tarif_plan_service.py
    │   ├── test_category_service.py
    │   ├── test_line_item_handler.py
    │   ├── test_checkout_handler.py
    │   ├── test_subscription_handlers.py
    │   ├── test_cancel_handler.py
    │   ├── test_admin_routes.py
    │   └── test_user_routes.py
    └── integration/
        ├── test_checkout_flow.py
        ├── test_subscription_lifecycle.py
        └── test_admin_operations.py
```

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create plugin skeleton: `__init__.py`, `admin-config.json`, `populate_db.py` | — |
| 2 | Move models (subscription, tarif_plan, addon, addon_subscription, category) | Model unit tests |
| 3 | Move repositories (all 5) | Repository unit tests |
| 4 | Move services (subscription, tarif_plan, category) | Service unit tests |
| 5 | Extract `checkout_service.py` from `checkout_handler.py` | Checkout unit tests |
| 6 | Create `SubscriptionLineItemHandler` (SUBSCRIPTION + ADD_ON) | Line item handler tests |
| 7 | Move event handlers (subscription_handlers, cancel_handler) | Handler unit tests |
| 8 | Move events (subscription_events, checkout_events) | — |
| 9 | Move scheduler jobs (expiration, trial, dunning) | — |
| 10 | Move routes (user: subscriptions, tarif_plans, addons; admin: all 3) | Route unit tests |
| 11 | Register in `plugins.json` + `config.json` | — |
| 12 | `register_line_item_handlers()` → register `SubscriptionLineItemHandler` | — |
| 13 | `register_event_handlers()` → subscribe to domain events | — |
| 14 | Move email templates (subscription_activated, subscription_cancelled) | — |
| 15 | Move integration tests | Integration tests green |
| 16 | `pre-commit-check.sh` — all green | — |

---

## Plugin Registration

### `plugins/plugins.json`
```json
"subscription": {
  "enabled": true,
  "version": "1.0.0",
  "installedAt": "",
  "source": "local"
}
```

### `plugins/config.json`
```json
"subscription": {
  "trial_days": 14,
  "dunning_intervals_days": [3, 7],
  "expiration_check_interval_seconds": 60,
  "max_subscriptions_per_user": 10,
  "allow_downgrade": true,
  "proration_enabled": true
}
```

---

## SubscriptionLineItemHandler

```python
class SubscriptionLineItemHandler(ILineItemHandler):
    def can_handle_line_item(self, line_item, context):
        return line_item.item_type in (LineItemType.SUBSCRIPTION, LineItemType.ADD_ON)

    def activate_line_item(self, line_item, context):
        # Extracted from CoreLineItemHandler — subscription + addon activation

    def reverse_line_item(self, line_item, context):
        # Extracted from CoreLineItemHandler — subscription + addon cancellation

    def restore_line_item(self, line_item, context):
        # Extracted from CoreLineItemHandler — subscription + addon restoration
```

---

## Acceptance Criteria

- `plugins/subscription/` is self-contained with all models, repos, services, routes, handlers
- All subscription/tarif/addon API routes work from the plugin blueprint
- `SubscriptionLineItemHandler` handles SUBSCRIPTION + ADD_ON line items
- Core's `CoreLineItemHandler` only handles TOKEN_BUNDLE
- `populate_db.py` seeds demo plans, categories, subscriptions
- All existing subscription tests pass (migrated to plugin tests/)
- `pre-commit-check.sh` passes
