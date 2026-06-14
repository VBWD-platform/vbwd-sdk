# S94 — RBAC naming consolidation + dead-code removal

**Status:** PLANNED — 2026-06-14 (re-scoped after a full RBAC trace; see §0)
**Repos:** `vbwd-backend` (core models, migrations, RBAC services/routes). **fe-admin only if the terminology alignment (DC-1) is taken** — the minimal plan keeps the API wire contract and leaves fe-admin untouched.
**Track:** RC-1 hygiene (with [S90 close-all-exposures](s90-close-all-exposures.md) — and **subsumes S90's G4** dead-decorator item).

**Why this sprint:** the owner flagged *"inconsistency in model and table naming for admin and user roles — ambiguous naming, duplicated functionality, or dead code."* An exhaustive runtime trace (below) **confirms all three**. The fix is to (a) remove the genuinely-dead code, (b) collapse the duplicated permission-resolution path to one, and (c) give the three "role" concepts a coherent, non-ambiguous naming scheme — **renaming live tables, not dropping them** (dropping the live joins would delete working RBAC features, which would be a breaking change, not cleanup).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · **Schema only via Alembic** ([[feedback_migrations_only]]) — every drop/rename a reviewed migration validated **up → down → up** · SOLID · DI · DRY · **core agnostic** (all core tables; the renames must not require any plugin change — verified) · **NO OVERENGINEERING** (rename + delete-dead only; no new abstraction) — [`_engineering_requirements.md`](_engineering_requirements.md). **Verify-dead-before-removing:** nothing is deleted/renamed without the grep proving its live/dead status (the §0 audit is that proof). No lint suppressions ([[feedback_no_noqa_without_permission]]).
**Gate:** `bin/pre-commit-check.sh --full` green on `vbwd-backend` (lint + unit + integration); the RBAC suite (`test_permission_system`, admin-access route tests, `test_user_role_*`) green; every migration up/down/up.

---

## 0. Audit — the actual RBAC graph (verified 2026-06-14, runtime-traced)

### The three "role" concepts and what each does at runtime

| # | Concept | Model / table(s) | Gates what, how |
|---|---|---|---|
| **A** | **Coarse role enum** (`SUPER_ADMIN/ADMIN/USER/VENDOR/BOT/GUEST`) | `User.role` → FK `vbwd_user_role` (singular, model **`RoleDefinition`**) | **Fallback/escape-hatch only.** `has_permission`/`has_user_permission` short-circuit `True` for `SUPER_ADMIN`, and for `ADMIN` *with no B/C assigned* (legacy). `vbwd/models/user.py:109-120,151-161`. |
| **B** | **Admin roles** (named, e.g. "Content Editor") | model **`Role`** / `vbwd_role`; join-to-perms `vbwd_role_permissions`; join-to-users `vbwd_user_roles` (plural) | **LIVE — gates `/admin`.** `@require_permission` → `g.user.has_permission()` iterates `assigned_roles` (eager `lazy="joined"` over `vbwd_user_roles`) → `Role.has_permission` over `vbwd_role_permissions` (`role.py:72-82`). |
| **C** | **User access levels** (fe-user feature tiers, plan-linked via `linked_plan_slug`) | model **`UserAccessLevel`** / `vbwd_user_access_level`; perms `vbwd_user_access_level_permissions`; users `vbwd_user_user_access_levels` | **LIVE — gates `/user`.** `@require_user_permission` → `g.user.has_user_permission()` iterates `assigned_user_access_levels` → `UserAccessLevel.has_permission`. |

### The three confirmed problems

1. **Ambiguous naming (the headline).** Three different things wear nearly-identical names: `vbwd_role` (admin roles, B), `vbwd_user_role` (the coarse-enum lookup, A), `vbwd_user_roles` (user↔admin-role join, B). Nobody can tell them apart by name.
2. **Naming *inversion* (the real trap).** The model **`Role` (B)** is surfaced to admins as **"Access Levels"** — `GET/POST /api/v1/admin/access/levels` manage `Role` (`routes/admin/access.py:73-242`). Meanwhile the model literally named **`UserAccessLevel` (C)** lives at **`/admin/access/user-levels`** (`access.py:262-370`). **Model names and UI labels are crossed.** This is the deepest source of "which is which".
3. **Duplicated functionality + dead code:**
   - **`vbwd/decorators/permissions.py`** (`require_permission`/`require_role`/`require_all_permissions`) — **dead**: zero routes import it (every route imports from `vbwd/middleware/auth.py`). A second, unused copy of the permission decorators.
   - **`RBACService`** (`services/rbac_service.py`) implements a **parallel** permission-*check* path (`has_permission`/`has_any_permission`/`has_all_permissions`, querying `vbwd_user_roles`→`vbwd_role_permissions`) that the **live** auth path never calls — only the dead decorator did. (Its **assign/grant** methods *are* live, used by `user_permission_grant.py` for S69.) → the check methods are redundant with `User.has_permission`.

### Genuinely-dead data (unrelated to roles, but in-scope cleanup)
- **`UserDetails.balance`** (`vbwd_user_details.balance`, `models/user_details.py:69`) — written only by the admin path (`user_service.py:350`), read only in `to_dict()`, **not** in the user schemas; live money is `UserTokenBalance`. **DEAD → drop.**
- **`vbwd_user_case`** / `UserCase` (`models/user_case.py`, `User.cases` backref, `UserCaseStatus`) — created in the big-bang migration, **never wired** (zero routes/services), only an infra "exists" assertion. **ORPHAN → drop.**

> **Net:** B and C are **two genuinely-live, distinct** permission systems (admins vs end-users) — neither is droppable. What's wrong is the **names** (ambiguous + inverted) and the **dead/duplicate permission code**. So this sprint **renames for clarity + deletes the dead/duplicate**, and drops the two truly-dead data items.

---

## 1. Target naming scheme

The coherent scheme (admin side = "admin role", user side = "access level", enum = its own lookup):

| What | Before | After (recommended) | Impact |
|---|---|---|---|
| Admin role model/table (B) | `Role` / `vbwd_role` | **`AdminRole` / `vbwd_admin_role`** | backend-only (no plugin imports `Role`) |
| Admin role↔perm join (B) | `vbwd_role_permissions` | **`vbwd_admin_role_permissions`** | backend-only |
| User↔admin-role join (B) | `vbwd_user_roles` (plural) | **`vbwd_user_admin_role`** | backend-only (`secondary=` table; ORM rel name unchanged) |
| Coarse-enum lookup (A) | `vbwd_user_role` (singular) / `RoleDefinition` | **keep** (`vbwd_user_role` / `RoleDefinition`) — now unambiguous once B's join is renamed | none |
| User↔access-level join (C) | `vbwd_user_user_access_levels` | **`vbwd_user_access_level_rel`** (matches S73 `vbwd_user_group_rel`) | backend-only (`secondary=` table; ORM rel name unchanged) |
| Access-level model/table (C) | `UserAccessLevel` / `vbwd_user_access_level` | **keep** (already consistent) — optionally `AccessLevel` under DC-1 | — |
| **API/UI terminology** | `/admin/access/levels` ⇒ **Role (B)**; `/user-levels` ⇒ AccessLevel (C) | **DC-1**: align so "roles" ⇒ B and "access levels" ⇒ C | touches fe-admin |

The model-class renames are safe because the audit shows **no plugin imports `Role`**, and the join renames move only `db.Table("…")` string literals + raw `insert/delete` SQL (the ORM relationship names — `assigned_roles`, `assigned_user_access_levels` — are unchanged, so plugins/auth code are untouched).

---

## 2. Slices

Each independent + gate-green.

### Slice 1 — Drop dead `UserDetails.balance`
Migration drops the column (down re-adds `Numeric(10,2) NOT NULL DEFAULT 0.00`); remove the column, the `to_dict()` key, and the `user_service.py:350` write + any admin-payload plumbing.
**TDD:** characterisation proves user-facing schema never carried it; admin `to_dict` no longer emits `balance`; up/down/up.

### Slice 2 — Drop orphan `vbwd_user_case` / `UserCase`
Migration drops table+indexes (down recreates from original DDL); remove `models/user_case.py`, the `__init__` exports, `UserCaseStatus`, the `User.cases` relationship, and the infra-test assertion.
**TDD:** `User` serialises without `cases`; `vbwd.models` no longer exposes `UserCase`; up/down/up.

### Slice 3 — Remove the duplicate/dead permission code (collapse to one path)
- **Delete `vbwd/decorators/permissions.py`** (dead duplicate) + its re-export in `vbwd/decorators/__init__.py`. (This is **S90 G4** — owned here.) Confirm-zero-importers first.
- **Trim `RBACService`** to only its live methods: keep assign/grant (used by `user_permission_grant.py` / S69); **remove the unused check methods** (`has_permission`/`has_any_permission`/`has_all_permissions`) **only after** grepping zero live callers (the dead decorator was the sole caller). If any remain, keep + document. **DC-2** governs how aggressive to be.
- Outcome: exactly **one** runtime permission check (`User.has_permission` / `has_user_permission`), no shadow implementation.
**TDD:** route auth unchanged (the live middleware path is untouched); S69 permission-grant tests green; a guard test asserts `decorators/permissions` is gone and nothing imports it.

### Slice 4 — Rename admin-role (System B) for clarity
`Role`→`AdminRole`; `vbwd_role`→`vbwd_admin_role`; `vbwd_role_permissions`→`vbwd_admin_role_permissions`; `vbwd_user_roles`→`vbwd_user_admin_role`.
- Migration: `rename_table` for all three + rename PK/FK/index constraints to the new prefix (so Postgres names don't drift); down reverses.
- Code: `__tablename__`+class in `role.py`, the assoc `db.Table` literals, all core refs (`role_repository.py`, `routes/admin/access.py`, `rbac_service.py`, `rbac_seeder.py`, `permission_catalog.py`, `bin/create_admin.py`, `bin/install_demo_data.py`, `models/__init__.py`, fixtures/tests).
- **Wire contract preserved** (response keys `role`/`slug`/`permissions` unchanged) → fe-admin untouched **unless** DC-1 is taken.
- Data-exchange: if a roles/access exchanger exists, `entity_key`+natural key (`slug`) unchanged — only the backing table moves; confirm round-trip green.
**TDD:** full RBAC suite green against the renamed tables; a migration test asserts the new table names + the FK to `vbwd_permission` survive; up/down/up.

### Slice 5 — Rename the access-level join (System C)
`vbwd_user_user_access_levels`→`vbwd_user_access_level_rel`.
- Migration: `rename_table` + constraint renames; down reverses. Code: the assoc `db.Table` literal + the raw `insert/delete` in `routes/admin/access.py:433,441,454`. ORM relationship names unchanged → `UserAccessLevelService` + the subscription `access_level_handler` untouched.
**TDD:** assign/revoke access-level round-trips green; subscription access-level integration green; up/down/up.

### Slice 6 (DC-1, optional) — Terminology alignment (API + fe-admin)
If the owner wants the inversion fixed end-to-end: rename the admin endpoints `/admin/access/levels`→`/admin/access/roles` (B) so "roles" means admin roles and "access levels" means C, and update fe-admin labels/routes/i18n accordingly (the "Access Levels" nav item → "Admin Roles"; the user-levels page → "Access Levels"). Optionally `UserAccessLevel`→`AccessLevel`. **Larger blast radius (API + fe-admin + e2e)** — only if DC-1 = full alignment.
**TDD:** fe-admin Vitest + e2e for the renamed routes/labels; backend route tests for the new paths (with a temporary 308 redirect or a clean cut per DC-1).

---

## 3. Out of scope
- **Dropping `vbwd_user_roles` / `vbwd_user_user_access_levels`** — they're live (B/C joins); S94 renames them. Removing the *features* (named admin roles, multi-access-level assignment) is a separate product decision, not cleanup.
- **Merging B and C into one system** — they serve different audiences (admin vs end-user); not a cleanup.
- **Renaming `vbwd_permission` / `RoleDefinition`** — left as-is (shared / now-unambiguous).
- **Reworking the `User.role` enum fallback semantics** — documented, not changed.

## 4. Acceptance / Definition of Done
1. `--full` green; all migrations up/down/up; no lint suppressions.
2. `UserDetails.balance` + `vbwd_user_case`/`UserCase` fully removed; imports clean; infra test updated.
3. Exactly one runtime permission-check path remains; `decorators/permissions.py` deleted; `RBACService` trimmed per DC-2 with S69 grants still green.
4. System B renamed to `AdminRole`/`vbwd_admin_role`/`vbwd_admin_role_permissions`/`vbwd_user_admin_role`; System C join renamed to `vbwd_user_access_level_rel`; RBAC suite green; `vbwd_user_role` (singular lookup) kept.
5. If DC-1 = full alignment: API + fe-admin terminology corrected (no more "Access Levels" meaning admin Roles); else the minimal backend-only rename ships and fe-admin is untouched.
6. Completion report `docs/dev_log/20260613/reports/NN-s94-rbac-cleanup.md` with the before/after name map + the as-built migration list.

## 5. Decisions to confirm (owner) + risks
**Decisions:**
- **DC-1 — terminology alignment depth.** *(a)* **Minimal** (recommended for RC-1): backend table/model rename only, API + fe-admin untouched (keeps `/admin/access/levels` meaning admin roles, documented). *(b)* **Full**: also rename API paths + fe-admin labels so "roles"=B and "access levels"=C (fixes the inversion but touches fe-admin + e2e). Slice 6 is gated on this.
- **DC-2 — `RBACService` trim.** Remove the unused check methods (recommended; live check is `User.has_permission`) vs keep them. Confirm `user_permission_grant.py` only uses assign/grant.
- **DC-3 — back-compat aliases.** Keep transitional `Role = AdminRole` export for one release? Recommended **no** (no external importer).
- **DC-4 — migration ordering.** Stack on the current core head; reconcile the open multi-head graph (S85 `drop_price`, TaxClass flatten) — merge as needed.

**Risks:**
- **Postgres constraint/index name drift** after `RENAME TABLE` → rename PK/FK/index in the same migration; assert new names in a migration test.
- **String-literal misses** — the joins are `db.Table("…")` literals + raw `insert/delete` (not ORM-name-driven); grep every literal; covered by assign/revoke integration tests.
- **Multi-head Alembic graph** ([[project_migration_graph_fragmentation]]) — validate `alembic upgrade heads` resolves with the real plugin set.
- **DC-1 full-alignment scope creep** — the API/label fix is the most valuable but also the broadest; keep it a separate slice so the safe backend cleanup can ship even if DC-1 is deferred.

## 6. Cross-references
- [S90 close-all-exposures](s90-close-all-exposures.md) — its **G4 (dead duplicate decorators)** is implemented here (Slice 3).
- Role-lookup origin (singular `vbwd_user_role` / `RoleDefinition`) — [report 09](../reports/09-s73-s74-user-groups-account-type-and-role-lookup.md).
- S69 plan/add-on permission grants — uses `RBACService` assign/grant (must stay green through Slice 3).
- [[feedback_migrations_only]] · [[project_migration_graph_fragmentation]] · [[feedback_no_direct_db_for_test_data]].
