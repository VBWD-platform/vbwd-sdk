# S69 — Plan/add-on driven user permissions (`permissions_enable` / `special_permissions_enable`)

**Status:** 🟢 DONE on disk — 2026-06-12 (see [report 07](../../20260611/reports/07-s69-plan-addon-driven-permissions.md)); not committed. DoD gate `--plugin subscription --full` green (144 unit / 79 integration); core port 9/9. Core `--full` has only **pre-existing, non-S69** meta-ratchet failures (report 07 §Core-gate honesty). fe-admin permission-list editor deferred to **S69.1**.

**Plugin:** `subscription` (consumer + emit gaps) + **core** (one new write port for RBAC) · **Depends on:** core RBAC (`Role` / `UserAccessLevel`), subscription lifecycle events (exist) · **Relates to:** the GHRM consumer pattern (events → reconcile), S51 D3 (security-guardrail flag).
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, **no overengineering**;
`bin/pre-commit-check.sh --plugin subscription --full` **and** core `--full` green = done. See
`docs/dev_log/20260526/sprints/_engineering-requirements.md`. **Subscription must not import core RBAC
models directly** — it goes through one narrow core port (DIP), the way GHRM uses
`ISubscriptionEntitlements`.

## Problem
There is no link between a tariff plan / add-on and a user's permissions. Activating a plan grants
the user **nothing** permission-wise; cancelling removes nothing. The seam half-exists
(`UserAccessLevel.linked_plan_slug`, `UserAccessLevelService.revoke_plan_linked_levels(user_id,
plan_slug)`) but nothing drives it. Two further realities make a naive handler unreliable:

1. **Lifecycle events are only partially emitted.** `subscription.activated` / `subscription.cancelled`
   fire on the **payment** path (`line_item_handler`) and provider-cancel path
   (`recurring_billing_subscriber`) — but the **admin** activate/cancel routes
   (`admin_subscriptions.py`), the **scheduler** trial/sub expiry (`subscription_service.expire_*`),
   and **all add-on** activation/cancellation (`line_item_handler._activate_addon`) emit **no event**.
2. **RBAC has no per-permission grant.** Permissions are only granted by assigning a **`UserAccessLevel`**
   (user-facing track) or a **`Role`** (admin track); the user's effective set is the **union** across
   assigned levels/roles. There is no "grant this one permission to this user" primitive, and no write
   port a plugin may call.

## Goal
When a subscription **or** add-on becomes active, the user gains the permissions declared in that
plan/add-on's config; when it ends (cancel / expire), they lose them — **unless** another still-active
plan/add-on grants the same permission. Driven by lifecycle events, **idempotent**, overlap-safe, and
incapable of accidental privilege escalation.

## Configuration (no migration — reuse existing JSON columns)
- **`TarifPlan.features`** (existing `JSON`, already serialized in `to_dict()`) gains two keys:
  - `"permissions_enable": [<permission id>, …]` — **user-facing** permissions (UserAccessLevel track).
  - `"special_permissions_enable": [<permission id>, …]` — **elevated / admin-track** permissions (Role
    track), gated (see D4).
- **`AddOn.config`** (existing `JSONB`) gains the same two keys.
- Permission ids are the dotted catalog strings (e.g. `shop.products.view`, `analytics.view`) from the
  permission catalog (`permission_catalog.collect_permission_catalog`). Unknown ids are skipped with a
  logged warning (never auto-created).

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Reconcile, not ad-hoc grant.** | On any lifecycle event for a user, **recompute the desired permission grants from the union of that user's ACTIVE/TRIALING plans + add-ons** and diff against what's assigned. Idempotent and self-correcting (covers missed/duplicated events). Overlap is automatic: the effective set is the union of assigned levels, so removing one source's level leaves permissions still backed by another source. No per-permission bookkeeping (no GHRM-style `repo_grants` needed here). |
| **D2 — Managed, source-scoped level/role.** | Each plan/add-on that declares config gets **one managed `UserAccessLevel`** (for `permissions_enable`) and, when enabled, **one managed `Role`** (for `special_permissions_enable`). Deterministic slugs: `auto-plan-<plan_slug>` / `auto-addon-<addon_slug>`. Marked `is_system=True` and set `linked_plan_slug` for plans (reuse the existing field + `revoke_plan_linked_levels`). The managed entity's permission set is **synced** to the config on each reconcile (add/remove perms to match), so editing the plan config and re-activating converges. Admins must not hand-edit `auto-*` entities (documented; `is_system` already discourages it). |
| **D3 — One narrow core write port.** | Add `IUserPermissionGrant` to **core** with idempotent methods the consumer needs: `ensure_user_access_level(slug, name, permission_names, *, linked_plan_slug=None) -> level_id`, `assign_level(user_id, level_id)`, `revoke_level(user_id, level_id)`, and the role equivalents `ensure_role(slug, name, permission_names)`, `assign_role(user_id, role_slug)`, `revoke_role(user_id, role_slug)`. Default impl is backed by the existing `UserAccessLevelService` / `RBACService` / repositories. Register it like `register_entitlement_provider()` (composition root) so subscription resolves the abstraction, never core models. |
| **D4 — Security guardrail on special (admin-track) perms.** | `special_permissions_enable` grants **admin-track** permissions → privilege escalation risk. Gated behind a core setting **`allow_plan_special_permissions` (default `false`)**: when off, `special_permissions_enable` is **ignored** (logged), no managed role is created/assigned. Even when on, reject the wildcard `*` and a deny-list of dangerous perms (`settings.system`, anything resolving to super-admin) at sync time. Mirrors S51 D3 (three layers: setting + sync-time validation + assignment clamp). `permissions_enable` (user-facing) is **not** gated. |
| **D5 — Close the emit gaps.** | Make the lifecycle events fire on **every** status-change path so reconcile is reliable: emit `subscription.activated` / `subscription.cancelled` from the **admin** activate/cancel routes and the **scheduler** expiry (`expire_subscriptions` / `expire_trials`, also emit `subscription.expired`→treated as cancel); add **`addon.activated` / `addon.cancelled`** events (`{user_id, addon_id, addon_slug}`) emitted from the add-on activate path and add-on cancellation. The consumer subscribes to all of them; each handler does the same `reconcile_user(user_id)`. |
| **D6 — Active = ACTIVE or TRIALING.** | Reconcile counts a source as granting if its subscription/add-on status is `ACTIVE` or `TRIALING`. Permission removal follows status immediately on cancel/expire (grace periods are a per-plugin concern, e.g. GHRM's GitHub grace — out of scope here). |

## Scope / files
**Core (one port + registration):**
- `vbwd/services/user_permission_grant.py` — `IUserPermissionGrant` (ABC, narrow) + `DefaultUserPermissionGrant` (delegates to `UserAccessLevelService`, `RBACService`, `UserAccessLevelRepository`/`RoleRepository`); a module-level `register_user_permission_grant()` / `resolve_user_permission_grant()` mirroring the entitlement-provider registry. Idempotent ensure/assign/revoke (no-op when already in desired state). Honors D4's deny-list + the `allow_plan_special_permissions` setting (read from core settings).
- Wire registration of the default provider at the app composition root (where `register_entitlement_provider` is wired).

**Subscription plugin (the consumer + emit gaps):**
- `subscription/services/subscription_read_model.py` — add `active_addon_ids(user_id) -> List[UUID]` (mirror `active_plan_ids`; ACTIVE/TRIALING add-on subscriptions).
- `subscription/services/permission_sync_service.py` — `PermissionSyncService` with `reconcile_user(user_id)`:
  1. Collect the user's active plans (`active_plan_ids`) + active add-ons (`active_addon_ids`); read each one's `permissions_enable` / `special_permissions_enable` from `features` / `config`.
  2. For each source with config: `ensure_user_access_level("auto-plan-<slug>", …, permission_names, linked_plan_slug=<slug>)` (+ `ensure_role` for special, when D4 allows) via the port, then `assign_level` / `assign_role`.
  3. For managed `auto-*` levels/roles the user holds whose source is **no longer active**: `revoke_level` / `revoke_role`.
  Pure orchestration over the port + read model; no core-model imports.
- `subscription/__init__.py` (or the plugin's `register_event_handlers`) — subscribe `subscription.activated`, `subscription.cancelled`, `addon.activated`, `addon.cancelled` → `reconcile_user(payload["user_id"])`. (Same in-process `event_bus` pattern as GHRM.)
- **Emit gaps (D5):** add `event_bus.publish(...)` calls in `admin_subscriptions.py` (activate + cancel), `subscription_service.expire_subscriptions` / `expire_trials`, and `line_item_handler._activate_addon` + the add-on cancel path. Reuse the existing `_publish_subscription_event` helper; add an analogous add-on emit.

**Out of scope (fast-follow S69.1):** fe-admin UI to edit `permissions_enable` / `special_permissions_enable` on the plan/add-on forms (a dual-list of catalog permissions, like S46's selectors). For this sprint the keys are set via import/export, seed, or API. Note it; do not build it here.

## TDD (tests first)
**Core port (`tests/unit`):**
- `ensure_user_access_level` is idempotent (creates once, syncs permission set on change); `assign/revoke_level` no-op when already in/out; unknown permission id skipped with warning.
- D4: with `allow_plan_special_permissions=false`, `ensure_role`/special path is a no-op; with it on, `*` and deny-listed perms (`settings.system`) are rejected.

**Subscription consumer (`plugins/subscription/tests`):**
- Activating a plan with `features.permissions_enable=["analytics.view"]` → after `reconcile_user`, `user.has_user_permission("analytics.view")` is true and a managed `auto-plan-<slug>` level is assigned.
- **Overlap:** two active plans both granting `analytics.view`; cancel one → `reconcile_user` keeps the permission (other source's level remains). Cancel the last → permission removed.
- Add-on with `config.permissions_enable` → activating the add-on grants; cancelling revokes (driven by the new `addon.activated`/`addon.cancelled` events).
- **Special perms:** `special_permissions_enable=["some.admin.perm"]` ignored when the flag is off; granted via a managed role when on; `*` rejected.
- **Emit gaps:** admin activate/cancel routes and scheduler expiry now publish the event and the user's permissions reconcile (regression for the silent admin/scheduler paths).
- **Idempotency:** running `reconcile_user` twice produces no duplicate level/role assignments; an unknown permission id is skipped, not fatal.

## Definition of done
A plan/add-on declaring `permissions_enable` / `special_permissions_enable` grants those permissions to
the user on activation (any path: payment, admin, trial→active) and removes them on cancel/expire unless
another active source still grants them; user-facing perms always apply, admin-track "special" perms only
when `allow_plan_special_permissions` is on and never for wildcard/deny-listed perms; subscription reaches
RBAC only through the new core port (no core-model imports); reconcile is idempotent; no DB migration
(config in existing `features`/`config` JSON); `bin/pre-commit-check.sh --plugin subscription --full` and
core `--full` green. Not committed ([[feedback_no_commit_without_ask]]).