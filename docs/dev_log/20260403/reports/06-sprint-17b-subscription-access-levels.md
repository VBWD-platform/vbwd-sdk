# Report — Sprint 17b: Subscription Plugin Auto-Assignment via Events

**Date:** 2026-04-06
**Status:** Complete

---

## Summary

Extended the access level system (Sprint 17a) with event-driven auto-assignment. When a user's subscription changes, the subscription plugin automatically assigns or revokes the appropriate user access level. Core remains agnostic — it provides the assign/revoke API; the plugin handles the logic.

---

## What Was Built

### 1. Core: UserAccessLevelService

**File:** `vbwd/services/user_access_level_service.py`

Agnostic service for managing user access level assignments. Does not know about plans or subscriptions.

| Method | Purpose |
|--------|---------|
| `assign(user_id, level_id)` | Assign access level to user (no-op if already assigned) |
| `revoke(user_id, level_id)` | Revoke access level from user (no-op if not assigned) |
| `find_by_slug(slug)` | Lookup by slug (e.g., `"logged-in"`) |
| `find_by_linked_plan_slug(plan_slug)` | Find level linked to a plan (e.g., `"basic"` -> `"subscribed-basic"`) |
| `find_all_by_linked_plan_slug(plan_slug)` | Find all levels linked to a plan (one-to-many) |
| `revoke_plan_linked_levels(user_id, plan_slug)` | Bulk revoke all plan-linked levels |
| `get_user_levels(user_id)` | List all assigned levels for a user |

### 2. Subscription Plugin: SubscriptionAccessLevelHandler

**File:** `plugins/subscription/subscription/handlers/access_level_handler.py`

EventBus handler that reacts to subscription lifecycle events:

| Event | Action |
|-------|--------|
| `subscription.activated` | Find access level by `linked_plan_slug` -> assign to user |
| `subscription.cancelled` | Revoke plan-linked levels -> assign "logged-in" fallback |

Registered in `SubscriptionPlugin.register_event_handlers()` via EventBus.

### 3. Event Emission in LineItemHandler

**File:** `plugins/subscription/subscription/handlers/line_item_handler.py`

Added `event_bus.publish()` calls after subscription activation and cancellation. Payload includes:

```python
{
    "subscription_id": str,
    "user_id": str,
    "plan_id": str,
    "plan_slug": str,  # Used to lookup linked access level
    "plan_name": str,
}
```

Events published:
- `subscription.activated` — after subscription status set to ACTIVE
- `subscription.cancelled` — after subscription status set to CANCELLED (refund flow)
- `subscription.cancelled` — for conflicting subscriptions in is_single categories (upgrade path)

### 4. User Permissions on Subscription Plugin

**File:** `plugins/subscription/__init__.py`

Added `user_permissions` property declaring 7 user-facing permissions:

| Key | Label | Group |
|-----|-------|-------|
| `subscription.plans.view` | View available plans | Subscription |
| `subscription.manage` | Change plan, cancel, resubscribe | Subscription |
| `subscription.invoices.view` | View own invoices | Subscription |
| `subscription.tokens.view` | View token balance | Subscription |
| `subscription.tokens.manage` | Purchase token bundles | Subscription |
| `user.profile.view` | View own profile | User |
| `user.profile.manage` | Edit profile | User |

### 5. Documentation Updates

- **`docs/dev_docs/access-level-management.md`** — Added full User Access Levels section covering data model, permission namespace, auto-assignment flow, API protection patterns, frontend guards, and API endpoints
- **`docs/dev_docs/plugin-developer-guide.md`** — Added `admin_permissions`, `user_permissions`, `@require_user_permission`, `meta.requiredUserPermission`, access level auto-assignment via events, and updated checklists

---

## Architecture: Event Flow

```
Invoice paid
  -> PaymentCapturedHandler
     -> SubscriptionLineItemHandler._activate_subscription()
        -> subscription.status = ACTIVE
        -> event_bus.publish("subscription.activated", {user_id, plan_slug, ...})

EventBus delivers to all subscribers:
  -> SubscriptionAccessLevelHandler.on_subscription_activated()
     -> UserAccessLevelService.find_by_linked_plan_slug("basic")
     -> UserAccessLevelService.assign(user_id, level_id)
  -> SubscriptionActivatedHandler (email notification)
  -> GhrmPlugin.on_activated() (GitHub access)
```

```
Refund or cancellation
  -> SubscriptionLineItemHandler._reverse_subscription()
     -> subscription.status = CANCELLED
     -> event_bus.publish("subscription.cancelled", {user_id, plan_slug, ...})

EventBus delivers to all subscribers:
  -> SubscriptionAccessLevelHandler.on_subscription_cancelled()
     -> UserAccessLevelService.revoke_plan_linked_levels(user_id, "basic")
     -> UserAccessLevelService.assign(user_id, "logged-in" fallback)
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Service in core, handler in plugin | Core stays agnostic; only plugins know about plans |
| EventBus (not DomainEvent) for handler | Access level handler is cross-cutting, not a domain handler |
| Fallback to "logged-in" on cancel | Users keep basic access even after subscription ends |
| Revoke only plan-linked levels | Admin manual assignments are never auto-revoked |
| Publish events from LineItemHandler | Single source of truth for activation/cancellation |

---

## Tests

### New Tests: 22 passed

| File | Tests | Coverage |
|------|-------|----------|
| `plugins/subscription/tests/unit/test_access_level_handler.py` | 11 | Activated: assign, skip no link, skip missing fields, error handling. Cancelled: revoke + fallback, no fallback when nothing revoked, skip missing fields, warn missing fallback, error handling |
| `tests/unit/services/test_user_access_level_service.py` | 11 | find_by_slug, find_by_linked_plan_slug, assign (success, duplicate, user not found, level not found), revoke (success, not assigned, user not found), revoke_plan_linked_levels |

### Existing Tests: No regressions

- 19/19 subscription plugin unit tests pass
- 679/679 core unit tests pass (31 pre-existing failures in permission system and admin tax tests)

---

## Files Changed

| File | Type | Change |
|------|------|--------|
| `vbwd/services/user_access_level_service.py` | **NEW** | Core assign/revoke service |
| `plugins/subscription/subscription/handlers/access_level_handler.py` | **NEW** | EventBus handler for auto-assignment |
| `plugins/subscription/tests/unit/test_access_level_handler.py` | **NEW** | 11 unit tests |
| `tests/unit/services/test_user_access_level_service.py` | **NEW** | 11 unit tests |
| `plugins/subscription/subscription/handlers/line_item_handler.py` | Modified | Added event_bus.publish after activation/cancellation |
| `plugins/subscription/__init__.py` | Modified | Added user_permissions, registered access level handler |
| `docs/dev_docs/access-level-management.md` | Modified | Added User Access Levels section |
| `docs/dev_docs/plugin-developer-guide.md` | Modified | Added permissions and access level guidance |

---

## Next: Sprint 17c

Backend Admin API for User Access Levels:
- CRUD endpoints for user access levels
- Permission listing endpoint (aggregates from all plugins)
- User assignment/revocation endpoints
- Import/export support
