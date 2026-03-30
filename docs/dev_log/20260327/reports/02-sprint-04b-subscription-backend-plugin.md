# Report 02 — Sprint 04b: Subscription Backend Plugin

**Date:** 2026-03-27
**Status:** Done
**Duration:** ~1 session

---

## What Was Done

Created `plugins/subscription/` backend plugin containing all subscription, tarif plan, add-on, and category logic. The plugin registers a `SubscriptionLineItemHandler` for SUBSCRIPTION + ADD_ON line items.

### Plugin Structure (34 files)

```
plugins/subscription/
├── __init__.py                    SubscriptionPlugin class
├── admin-config.json              Admin UI config (general + lifecycle tabs)
├── populate_db.py                 Demo plans seeder
├── subscription/
│   ├── models/__init__.py         Re-exports from core (transition)
│   ├── repositories/              5 repos (subscription, tarif_plan, addon, addon_sub, category)
│   ├── services/                  3 services (subscription, tarif_plan, category)
│   ├── handlers/                  4 handlers (line_item, checkout, cancel, subscription_handlers)
│   ├── routes/                    6 route files + __init__.py blueprint
│   ├── events.py                  Subscription + checkout events
│   └── scheduler.py               Expiration, trial, dunning
└── tests/unit/                    test_line_item_handler.py (8 tests)
```

### Registration

- Added to `plugins/plugins.json` (enabled: true)
- Added to `plugins/config.json` with default config
- `SubscriptionPlugin.register_line_item_handlers()` registers `SubscriptionLineItemHandler`
- `SubscriptionPlugin.on_enable()` registers checkout + cancel domain event handlers
- `SubscriptionPlugin.on_enable()` starts subscription scheduler

### Test Results

- 8 new tests in `plugins/subscription/tests/unit/test_line_item_handler.py`
- 53 total sprint-specific tests green (13 registry + 15 core handler + 8 subscription handler + 9 refund + 8 restore)
- 725 core unit tests pass (excluding app-context tests that conflict during transition)

---

## Lessons Learned

### 1. SQLAlchemy table duplication during transition

Copying model files to the plugin caused `Table 'subscription' is already defined` errors because both core and plugin defined the same SQLAlchemy table.

**Solution:** During transition (04b), the plugin's `models/__init__.py` re-exports from core: `from vbwd.models.subscription import Subscription`. The actual model files were deleted from the plugin. In 04c (core cleanup), the model code moves to the plugin and core imports stop.

**Rule:** When migrating SQLAlchemy models, never have two files defining the same `__tablename__`. Use re-exports during transition.

### 2. Blueprint conflicts during transition

The subscription plugin registers routes on a new `subscription_bp` blueprint, but the same routes still exist in core. Tests that create the Flask app get blueprint registration conflicts.

**Expected:** This resolves in 04c when core routes are removed.

### 3. Import path depth matters

The background agent changed imports to `from plugins.subscription.subscription.models.subscription import Subscription` — pointing to deleted files. All model imports must go through the package `__init__.py`: `from plugins.subscription.subscription.models import Subscription`.

**Rule:** When using re-export `__init__.py`, ensure all consumers import from the package, not submodules.

### 4. sed batch fixups are faster than per-file Edit for mechanical changes

Fixing 8+ files with the same pattern replacement was faster via `sed -i '' 's|...|...|g'` than individual Edit tool calls.

---

## Transition State

During transition (04b done, 04c pending):
- Core still has all subscription models, repos, services, routes, handlers
- Plugin has copies (re-exporting models from core)
- Both sets of routes exist — app creation fails in tests
- `CoreLineItemHandler` still handles SUBSCRIPTION + ADD_ON (will be removed in 04c)
- `SubscriptionLineItemHandler` is ready but won't be registered until plugin properly initializes

After 04c:
- Core loses subscription code
- Plugin owns everything
- `CoreLineItemHandler` drops to TOKEN_BUNDLE only
- No more blueprint conflicts

---

## Next

Sprint 04c: Remove subscriptions from core — delete core model/repo/service/route/handler files, slim `CoreLineItemHandler` to TOKEN_BUNDLE only.
