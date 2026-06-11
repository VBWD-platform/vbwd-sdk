# S73 — User Groups (new core entity) + subscription-driven group membership

**Area:** **core** `vbwd-backend` (new model + CRUD + list + data-exchange + membership port) + `vbwd-fe-admin` (settings page, nav, user-edit selector) + plugin `subscription` (event-driven membership) · **Depends on:** core user model (exists), unified data-exchange (exists, json+csv), `DualListSelector` (exists), the S69 event/reconcile/port pattern (mirror it; if S69 lands first, reuse its emit-gap fixes).
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering; core stays agnostic (subscription reaches user-groups only through a core port — never imports the model). Guard: core `--full` + `--plugin subscription --full` + fe-admin Vitest/ESLint green. See `docs/dev_log/20260526/sprints/_engineering-requirements.md`. **Not committed.**

> Note: the user's stray line "on fe-user any price can be shown brutto or netto" is **not** part of this sprint — it's [S72.4](s72-4-netto-brutto-display.md).

## Problem
There is no "user group" concept. We need a first-class, hierarchical, multilingual grouping of users (a user may be in several groups or none), manageable in admin (list + bulk + import/export), assignable on the user-edit page, and **automatically updated when a user buys a plan/add-on** whose config declares a check-in / check-out group.

## New data model (core)
- **`UserGroup`** — table **`vbwd_user_groups`**: `id` (PK), `slug` (String, **unique**, indexed, NOT NULL), `name` (String NOT NULL), `lang` (String(8), e.g. `en`), `parent_group` (String, nullable — references another group's `slug`, self-referential hierarchy by slug), timestamps. `to_dict()` → `{id, slug, name, lang, parent_group, created_at, updated_at}`. (Slug-based parent keeps import/export portable across instances.)
- **`vbwd_user_group_rel`** — M2M membership: `user_id` (FK `vbwd_user.id` `ON DELETE CASCADE`), `group_slug` (FK `vbwd_user_groups.slug` `ON DELETE CASCADE`), PK `(user_id, group_slug)`. A user may have **0..N** rows. (Keyed by **slug** per the spec; `slug` is unique so it's a valid FK target.)
- **Migration** (core): create both tables; `down_revision` = core head `20260608_inv_admin_idx` (verify). Naming `20260611_*_user_groups.py`.

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Core entity + slug-keyed membership.** | `UserGroup` is core (like Role / UserAccessLevel). Membership stored by `group_slug` (the spec's `vbwd_user_group_rel`). Hierarchy via `parent_group` slug (display/grouping only in this sprint — no permission inheritance). |
| **D2 — One narrow core write port** `IUserGroupMembership`. | `list_user_group_slugs(user_id) -> set[str]`, `set_user_groups(user_id, slugs)` (replace-set), `add(user_id, slug)`, `remove(user_id, slug)`, idempotent. Subscription uses this port (DIP) — never imports `UserGroup`. Mirrors S69's `IUserPermissionGrant`. |
| **D3 — Subscription config drives membership via reconcile.** | Plan `features` / add-on `config` (existing JSON, **no migration**) may declare `user_checkin_group: <slug \| [slug]>` and/or `user_checkout_group: <slug \| [slug]>`. On any subscription/add-on lifecycle event, **reconcile** the user's **managed** group memberships from the union of active sources (mirror S69's reconcile + the same emit-gap closing for admin/scheduler/add-on paths). |
| **D4 — Reconcile semantics (managed-only; check-out wins).** | *Managed groups* = every slug mentioned by any of the user's **active** sources' check-in/check-out config. For each managed group: desired = **(some active source checks-in)** AND **NOT (any active source checks-out)** — check-out takes precedence. Apply add/remove to match. **Never touch un-managed memberships** (groups no source mentions stay admin-controlled). Idempotent; overlap-safe (the union self-resolves, like S69). A check-out removal is not auto-restored after the source ends unless another active source checks the user back in (documented). |

## Scope
**Core backend:**
- `vbwd/models/user_group.py` (`UserGroup`) + the `vbwd_user_group_rel` table; repo + `UserGroupService` (CRUD, list, slug validation, bulk delete; `parent_group` must reference an existing slug or be null).
- Membership: `vbwd/services/user_group_membership.py` — `IUserGroupMembership` (ABC) + default impl over the rel table; `register/resolve_user_group_membership()` (mirror the entitlement-provider registry).
- Admin routes `vbwd/routes/admin/user_groups.py` → `/api/v1/admin/user-groups` CRUD + **bulk** (`POST .../bulk-delete`), gated `settings.manage`; plus user membership `GET|PUT /api/v1/admin/users/<id>/groups` (replace-set of slugs, gated `users.manage`) and `group_slugs` accepted on the core user update payload.
- **Data-exchange:** a `user_groups` exchanger (`BaseModelExchanger`, `natural_key="slug"`, `cluster=CLUSTER_SETTINGS`, `supported_formats={"json","csv"}`, `public_fields=[slug, name, lang, parent_group]`). Extend the existing `users` exchanger to carry `group_slugs` so user import/export round-trips memberships (by slug).

**fe-admin:**
- New page `vue/src/views/UserGroups.vue` at route `settings/user_groups` (`{ path: 'settings/user_groups', name: 'user-groups', meta: { requiredPermission: 'settings.manage' } }`) — a typical list (search/sort), **bulk operations** (select + bulk delete), and embedded `ImportExportControls` for `user_groups` (json/csv). Create/edit form: slug, name, lang, parent_group (select of existing groups).
- **Nav:** add to the core `settings` section in `AdminSidebar.vue`, **directly below Access Levels**: `{ label: t('nav.userGroups'), to: '/admin/settings/user_groups', id: 'user-groups', requiredPermission: 'settings.manage' }` (auto test-id `nav-item-settings-user_groups`).
- **User-edit group selector:** on `vue/src/views/UserEdit.vue`, add a **Groups** block using `vue/src/components/DualListSelector.vue` (`modelValue=group_slugs`, `options=` all groups by slug); load current via `GET .../groups`, save via `PUT .../groups` (or in the user update payload).
- i18n: `nav.userGroups`, page/form/tag keys (all locales).

**Subscription plugin (mirror S69):**
- A consumer subscribing to `subscription.activated` / `subscription.cancelled` (+ `addon.activated` / `addon.cancelled`, and the admin/scheduler emit-gaps — shared with S69) → `reconcile_user_groups(user_id)`:
  1. Gather active plans + add-ons (`active_plan_ids` + `active_addon_ids` from the read model), read `user_checkin_group` / `user_checkout_group` from each `features`/`config`.
  2. Compute managed-group desired set per D4; apply via `IUserGroupMembership` (resolved from the container).
- No core-model imports; reads its own plan/add-on config only.

**Out of scope (fast-follow):** admin UI to edit `user_checkin_group`/`user_checkout_group` on plan/add-on forms (set via import/export, seed, or API for now); permission inheritance through `parent_group`.

## TDD (tests first)
**Core:** UserGroup CRUD + slug uniqueness + `parent_group` must exist or be null; membership add/remove/set is idempotent and slug-keyed; bulk delete; deleting a group cascades its rel rows; `user_groups` exchanger json+csv round-trip (by slug, parent_group portable); user import/export carries `group_slugs`.
**Subscription (mirror S69):** activating a plan with `features.user_checkin_group="vip"` adds the user to `vip`; `user_checkout_group="trial"` removes them from `trial` on activation; **check-out wins** when both reference the same group across active sources; cancelling the only check-in source removes the managed membership (reconcile); un-managed memberships are never touched; add-on check-in/out works; idempotent re-run.
**fe-admin (Vitest):** nav item under Access Levels routes to the page; list + bulk delete + import/export controls render; the user-edit Groups selector lists groups, pre-selects current, saves `group_slugs`.

## Definition of done
`UserGroup` (`vbwd_user_groups`) + slug-keyed membership (`vbwd_user_group_rel`) exist with core CRUD, a `/admin/settings/user_groups` list (bulk + json/csv import/export) under a nav item below Access Levels, and a group selector on the core user-edit page; a user may belong to many groups or none; buying a plan/add-on with `user_checkin_group` / `user_checkout_group` config updates the user's **managed** memberships via reconcile (check-out wins, overlap-safe, un-managed memberships untouched); subscription reaches groups only through the core port; all touched repos green under `--full` + fe Vitest/ESLint. Not committed ([[feedback_no_commit_without_ask]]).
