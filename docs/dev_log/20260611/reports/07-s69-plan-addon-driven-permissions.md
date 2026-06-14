# Report 07 — S69: plan/add-on driven user permissions

**Date:** 2026-06-12 · **Sprint:** [S69](../../20260610/done/s69-user-permissions-special-perms-subscription.md) · **Repos:** core `vbwd/` (one new write port) + `plugins/subscription` (consumer + lifecycle emit-gap closure). Plugin code gitignored; core change is purely additive (one new service + its test). **Not committed.**
**DoD gate `bin/pre-commit-check.sh --plugin subscription --full`: GREEN** — Part A lint · Part B **144 unit** · Part C **79 integration**. Core port unit suite **9/9** green. TDD-first (19 new tests, RED before GREEN).

> **Core `--full` caveat (not caused by S69) — RESOLVED, see [report 08](08-core-full-gate-green.md).** At S69's completion the whole-repo core gate was not fully green, but every failure predated S69 (verified by attribution below). Follow-up: `core --full` is now **green on the CI/in-container path** (lint + 3806 unit + 672 integration); the only genuine fix was two taro config tests, and the meta-ratchets turned out to be outside the gate's path scope. S69 adds no repository and no datetime call, so it moves neither core meta-ratchet regardless.

---

## What S69 delivers

A tariff plan or add-on can now declare RBAC permissions in its existing JSON config (`TarifPlan.features` / `AddOn.config`), and the user gains/loses them as the subscription/add-on goes ACTIVE/TRIALING → cancelled/expired — **idempotent, overlap-safe, no privilege escalation, no DB migration**.

- `features.permissions_enable: [<permission id>, …]` → user-facing track (UserAccessLevel).
- `features.special_permissions_enable: [<permission id>, …]` → admin track (Role), gated (D4).
- Same two keys on `AddOn.config`.

## Core — one narrow write port (D3)

**`vbwd/services/user_permission_grant.py`** (new) mirrors the established `entitlement.py` registry pattern exactly:
- `IUserPermissionGrant` (ABC): `ensure_user_access_level(slug, name, permission_names, *, linked_plan_slug=None) -> level_id`, `assign_level` / `revoke_level`, `ensure_role(slug, name, permission_names)`, `assign_role` / `revoke_role` (+ the two narrow read helpers the reconcile-diff needs to revoke stale `auto-*` entities without the consumer importing core models).
- `DefaultUserPermissionGrant` delegates to `UserAccessLevelService` / `RBACService` / `RoleRepository`+`PermissionRepository`. `ensure_*` creates the managed `is_system=True` entity once (slug-keyed) and **syncs** its permission set to config on every call (add missing / drop extra — D2). `assign_*`/`revoke_*` are no-ops when already in/out of the desired state. An **unknown permission id is skipped with a logged warning, never auto-created**.
- **D4 guardrail** (three layers like S51 D3): the special/Role path reads core setting `allow_plan_special_permissions` (default `False`, via `current_app.config` with the same `RuntimeError` guard as `entitlement.py`) — when off it is a logged no-op (no role created/assigned); when on it rejects the wildcard `*` and a deny-list module constant (`settings.system` + super-admin) at sync time. The `permissions_enable` level track is never gated.
- Module registry: `register_user_permission_grant` / `clear_user_permission_grant` / `resolve_user_permission_grant`. **Wiring matches entitlement exactly** — core registers no default at the composition root; `resolve_*` falls back to a fresh `DefaultUserPermissionGrant()` when none is registered, and the consumer just calls `resolve_*`. No new wiring style invented; app factory untouched.

## Subscription — consumer + emit gaps

- `subscription_read_model.py`: new `active_addon_ids(user_id)` (ACTIVE/TRIALING, mirrors `active_plan_ids`); `addon_subscription_repository.py` gained `find_active_by_user_list` (the existing `find_active_by_user` was ACTIVE-only).
- `permission_sync_service.py` (new): `PermissionSyncService.reconcile_user(user_id)` (D1) — recompute desired grants from the union of the user's active plans + add-ons, `ensure_*`+`assign_*` per source with config (slugs `auto-plan-<slug>` / `auto-addon-<slug>`, `linked_plan_slug` for plans), then `revoke_*` any managed `auto-*` entity the user holds whose source is no longer active. **Pure orchestration over the port + read model — no core RBAC model imports** (verified).
- `lifecycle_events.py` (new): DRY home for the EventBus publishes + event-name constants; `permission_sync_handler.py` (new): subscribes and calls `reconcile_user` then commits.
- `__init__.py` `register_event_handlers`: subscribes `subscription.activated`/`cancelled`/`expired` + `addon.activated`/`cancelled`.
- **D5 emit gaps closed (all five sites confirmed to exist before editing):** admin activate + cancel routes (`admin_subscriptions.py`); `subscription_service.expire_subscriptions` (→ `subscription.expired`) and `expire_trials` (→ `subscription.cancelled`); `line_item_handler._activate_addon` + `_reverse_addon` (→ new `addon.activated`/`addon.cancelled` with `{user_id, addon_id, addon_slug}`). The payment-path `_publish_subscription_event` was refactored to delegate to the shared helper (DRY).

## Tests (19 new, RED-first)

- Core (`tests/unit/services/test_user_permission_grant.py`, 9): ensure idempotent + permission-set sync; assign/revoke no-op when already in/out; unknown id skipped with warning; D4 special path no-op when flag off, `*` and `settings.system` rejected when on.
- Subscription (10 integration): plan grant → `has_user_permission` true + managed level assigned; **overlap** (two plans grant the same perm; cancel one → kept, cancel last → removed); add-on grant/revoke via the new events; special perms gated; emit-gap regression (admin + scheduler paths now reconcile); idempotency (reconcile twice → no duplicates; unknown id non-fatal); `active_addon_ids` integration.

## Core-gate honesty (why core `--full` isn't fully green — none of it S69)

1. **`tests/meta/test_repository_coverage.py`** flags `seed_marker_repository` (**committed since S30 / `fc1bd6a`, no test, `EXPECTED_GAPS` empty → this ratchet was already RED at HEAD before this session**) and `device_token_repository` (uncommitted **S66** work). S69 adds no repository.
2. **`tests/meta/test_datetime_tz_backlog.py`** grew 17→18 on an ambient **booking** plugin `datetime.utcnow()` site (`plugins/booking/...`). Not S69, not S66/S79.
3. The broader cross-plugin Part C cascade the implementer observed is a dirty `vbwd_test` DB (`CREATE TYPE userstatus already exists` enum collision + shared state); affected tests pass after a clean `vbwd_test` recreate, and S69's two integration files pass in isolation.

**None regress on S69.** Closing items 1–2 (write `device_token_repository` + `seed_marker_repository` repo tests; fix the booking datetime site) and recreating the clean test DB would make core `--full` green, but those are pre-existing/other-sprint backlog, deliberately left outside S69's scope.

## Deviations

None from D1–D6. One additive detail: the port exposes two narrow read helpers (list assigned managed levels/roles, slug→id) so the consumer can revoke stale `auto-*` entities through the DIP boundary without importing core models — the minimal addition that makes D1's reconcile-diff possible. Out-of-scope honored: no fe-admin UI to edit the permission lists (deferred **S69.1**); keys are set via import/export/seed/API.
