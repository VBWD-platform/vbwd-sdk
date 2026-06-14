# Report 09 — S73 User Groups, S74 Account Type, and the User-Role lookup table

**Date:** 2026-06-13
**Author:** Claude (orchestrator) + `vbwd-tdd` agents
**Scope:** core `vbwd-backend`, `vbwd-fe-admin`, `vbwd-fe-user`
**Status:** all three DONE on disk, gate-green for their scope. **Not committed** (no-commit rule).

---

## Summary

Three core data-model features landed in one session, each implemented test-first by the
`vbwd-tdd` agent and verified against `bin/pre-commit-check.sh`:

1. **S73 — User Groups** (new core entity + subscription-driven membership)
2. **S74 — User account type** (private person / business on `UserDetails`)
3. **User-Role lookup table** (ad-hoc request): `User.role` native PG enum → varchar **FK** into a real `vbwd_user_role` table

All three are pure-core changes (no plugin coupling beyond S73's subscription consumer, which
reaches core only through a narrow port). The core agnosticism AST oracle stayed green throughout.

---

## S73 — User Groups

**Spec:** `docs/dev_log/20260613/done/s73-user-groups.md`

**What shipped:**
- **Core model** `vbwd/models/user_group.py` — `UserGroup` (table `vbwd_user_groups`: `id` PK, `slug`
  unique+indexed+NOT NULL, `name`, `lang`, `parent_group` self-ref by slug, timestamps) + the
  `vbwd_user_group_rel` M2M table (`user_id` FK→`vbwd_user.id`, `group_slug` FK→`vbwd_user_groups.slug`,
  both `ON DELETE CASCADE`, composite PK).
- **Repo + `UserGroupService`** — CRUD, slug validation, `parent_group` must reference an existing
  slug or be null, bulk delete.
- **Membership port** `vbwd/services/user_group_membership.py` — `IUserGroupMembership` ABC
  (`list_user_group_slugs`, `set_user_groups` replace-set, `add`, `remove` — idempotent) + default
  impl over the rel table + register/resolve registry (mirrors S69's `IUserPermissionGrant`).
- **Admin routes** `vbwd/routes/admin/user_groups.py` — `/api/v1/admin/user-groups` CRUD + `bulk-delete`
  (`settings.manage`); `GET|PUT /api/v1/admin/users/<id>/groups` (`users.manage`); `group_slugs`
  accepted on the core user-update payload.
- **Data-exchange** — a `user_groups` exchanger (`natural_key="slug"`, json+csv, `parent_group`
  portable); the `users` exchanger extended to round-trip `group_slugs` by slug.
- **Subscription plugin** — `group_sync_service.py` + `group_sync_handler.py` consuming
  `subscription.{activated,cancelled,expired}` + `addon.{activated,cancelled}` (mirroring S69's emit-gap
  coverage). Reconcile semantics **D4**: managed-only, **check-out wins**, overlap-safe, un-managed
  memberships untouched, idempotent. Reads plan `features` / add-on `config`
  (`user_checkin_group` / `user_checkout_group`); reaches groups **only via the port**, never imports
  `UserGroup`.
- **fe-admin** — `UserGroups.vue` at `settings/user_groups` (list, bulk-delete, json/csv
  import/export, create/edit form); nav item directly below Access Levels in `AdminSidebar.vue`;
  `DualListSelector` Groups block on `UserEdit.vue`; `nav.userGroups` + form/tag i18n in all locales.

**Migration:** `20260611_1000_user_groups` (down_revision `20260613_1100_flatten_tax_cls` — the actual
core head at S73 time, not the older head named in the spec).

**Gate (S73 scope):** core lint PASS · core unit 1606→1631 passed · agnosticism oracle PASS ·
`--plugin subscription --full` Part A/B green, integration 103 passed (2 failures pre-existing S85.1
price-float, not S73) · fe-admin Vitest 866→871 passed · fe-admin ESLint 0 errors.

**Side-fix during S73:** `plugins/subscription/tests/conftest.py` had a per-test `create_all()`/`drop_all()`
`db` fixture that stranded the `userstatus` ENUM and deadlocked when the whole subscription integration
suite ran together (the same failure mode the cms conftest fix already solved). Converted to a
session-scoped schema build (`DROP SCHEMA public CASCADE` + `create_all` once) with per-test `TRUNCATE`
isolation — took the subscription integration suite from flaky (99p/4f/4e) to stable (103p/2f).

---

## S74 — User account type (private / business)

**Spec:** `docs/dev_log/20260613/done/s74-user-account-type.md`

**What shipped:**
- **`AccountType(str, Enum)`** (`private`/`business`) in `vbwd/models/enums.py` — single source of truth
  (`AccountType.values()`).
- **`UserDetails.account_type`** (`String(16)`, NOT NULL, `server_default='private'`); `to_dict()`
  emits it; `validate_account_type()` + `AccountTypeValidationError` home the rule.
- **Validation across all write paths** (`update_user_details`, `admin_update`, `admin_create`):
  unknown value → error; `business` requires `company`. Surfaced as 400/409 on `vbwd/routes/user.py`,
  `routes/admin/users.py`, `routes/admin/profile.py`. Schema `OneOf` validators on the user-details
  schemas.
- **Invoice party rendering** — `_build_customer_party()` extracted in `vbwd/routes/invoices.py`:
  business → company name + VAT; private → person name. Narrow change only where the party was
  already assembled. PDF template renders VAT for business and avoids double-printing company.
- **Data-exchange** — `account_type` added to the user-details export/import field set (round-trips).
- **fe-admin** — Account-type select on `UserEdit.vue`; Company (required) + Tax shown only when
  Business; i18n in all 8 locales.
- **fe-user** — same select + conditional/required Company on `Profile.vue`; i18n in all 8 locales.

**Migration:** `20260613_1400_user_account_type` (down_revision `20260613_1300_add_guest_role`; single
core head; up→down→up validated).

**Gate (S74 scope):** core `--full` — lint PASS, 1631 unit, 187 integration (1 skipped), agnosticism
oracle PASS; new S74 tests 40 passed. fe-admin Vitest 871 + ESLint 0 errors. fe-user Vitest 886
(1 skipped) + ESLint 0 errors.

---

## User-Role lookup table (ad-hoc request)

**Request:** Replace the `User.role` string enum (`BOT, GUEST, USER, ADMIN, SUPER_ADMIN`, plus the
existing `VENDOR`) with rows in a `vbwd_user_roles` table; store the role slug as a FK; each role row
has a capitalised slug as `id` and a `name`.

**What shipped:**
- **New model** `vbwd/models/user_role.py` → **`RoleDefinition`** (class name avoids collision with the
  `UserRole` enum). Standalone `db.Model` (string PK, so it cannot extend the UUID-PK `BaseModel`).
  Columns: `id` `String(32)` PK = the capitalised slug (`"SUPER_ADMIN"`, `"ADMIN"`, `"USER"`,
  `"VENDOR"`, `"BOT"`, `"GUEST"`), `name` `String(64)` human-readable. `to_dict()` → `{id, name}`.
  `canonical_role_rows()` / `human_readable_role_name()` derive the seed set from the `UserRole`
  enum (DRY, single source of truth).
- **`vbwd_user.role`** changed from native PG enum to
  `db.Enum(UserRole, native_enum=False, length=32, create_constraint=False)` +
  `ForeignKey("vbwd_user_role.id")`. `native_enum=False` keeps the ORM attribute a `UserRole` member
  (so every `user.role == UserRole.ADMIN` comparison and `is_admin`/`effective_permissions` logic is
  unchanged), while the underlying column is plain VARCHAR the FK can target. The native `userrole`
  PG type is dropped. Wire contract unchanged (`to_dict()` still emits the slug string).
- **Two-path seeding:** the migration creates the table, inserts the 6 rows (`ON CONFLICT DO NOTHING`),
  converts the column (`USING role::text`, value-preserving), adds the FK, and drops the enum type.
  An `after_create` DDL event on `RoleDefinition.__table__` seeds the 6 rows whenever the schema is
  built via `create_all` (dev bootstrap + the integration-test schema builder) — without this, every
  user insert under a fresh test DB would violate the new FK.

**Migration:** `20260613_1500_user_role_lookup` (down_revision `20260613_1400_user_account_type`;
single core head; up→down→up validated twice — throwaway DB and live chain; downgrade restores the
native enum and value preservation confirmed).

**Naming deviation (needs owner sign-off):** the spec name `vbwd_user_roles` was **already taken** —
it is the pre-existing RBAC user↔access-level **join** table (`vbwd.models.role.user_roles`). To avoid
renaming a long-lived join table (a larger, riskier change), the new lookup table was named the
**singular `vbwd_user_role`**. So there are now two similarly-named tables:
`vbwd_user_roles` (RBAC join, unchanged) and `vbwd_user_role` (new role-definition lookup). If the
plural name is required for the lookup, the RBAC join table must be renamed first.

**Gate (role scope):** core `--full` Part A (lint) PASS, Part B (unit) 1637 passed; targeted role
unit/integration/migration suites + `test_model_table_consistency` + agnosticism oracle all green.
`test_enum_values_match_database` now passes for `role` (the non-native column self-skips the
`enum_range` check; the native type no longer exists).

---

## Migration chain (this session)

```
… → 20260613_1100_flatten_tax_cls
   → 20260611_1000_user_groups          (S73)
   → 20260613_1200_tags_cf (merge)      (S77 core slice, separate work)
   → … → 20260613_1300_add_guest_role
   → 20260613_1400_user_account_type    (S74)
   → 20260613_1500_user_role_lookup     (role lookup)   ← current single core head
```

---

## Known-red / not-ours

- **Whole-repo `--full` (all plugins together)** explodes with the documented fragmented cross-plugin
  migration-graph + concurrent-sprint failures (taro real-LLM API keys, withdraw/shop/booking
  price-float, cms/meinchat_plus cross-suite ENUM pollution). The correct verification scope —
  core `--full` and per-plugin `--full` separately — is green except for the noted pre-existing items.
- **Subscription integration:** 2 pre-existing S85.1 price-float failures (`'2.5' == '2.50'`, schema
  fingerprint) — not from this work.
- **Pre-existing uncommitted tree:** tax/currency/token-bundle/guest-role/price-float changes from
  other concurrent sprints are in the working tree; not authored here.
- **Operational:** the shared `vbwd_test` DB can be left with stranded ENUMs after an all-plugins
  `--full`; reset with `DROP SCHEMA public CASCADE` before re-running a core/per-plugin gate.

---

## Engineering requirements honored

TDD-first · SOLID/DI/DRY/Liskov · clean code · **no overengineering** (no role admin CRUD/UI was
added — table + FK + seeding only; S73 kept the subscription consumer behind the port). Quality guard:
`bin/pre-commit-check.sh`. No lint suppressions added. **Nothing committed.**
