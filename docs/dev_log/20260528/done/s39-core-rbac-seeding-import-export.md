# S39 — Core RBAC default seeding (roles + permissions) via the seeder, not create_admin; import/export round-trip; subscription seeds plan-linked access levels

> **Renumbered S38 → S39** — s38 is the meinchat Redis-bus hardening sprint.

**Status:** IMPLEMENTED (backend) — 2026-05-29 (decisions negotiated + locked §8)
**Repos touched:** `vbwd-backend` (core: `vbwd/`) + `vbwd-backend/plugins/subscription/` + `vbwd-demo-instances` (deploy wiring).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --full` GREEN on backend (+ `--plugin subscription`); idempotency proven by re-run tests; no raw SQL (services/repos only).

---

## 1. Problem

The granular RBAC tables (`vbwd_role`, `vbwd_permission`, `vbwd_user_access_level`) are **empty on every instance** — local and vbwd.cc — because **nothing seeds them**:

- `bin/create_admin.py` (run from CI via `create-admin.sh`) only sets the coarse **`UserRole` enum** (`SUPER_ADMIN`/`ADMIN`/`USER`) on the user. It does **not** create granular roles/permissions. **This enum-only path is a temporary fallback** (per product decision 2026-05-29).
- `flask seed-test-data` (gated behind `TEST_DATA_SEED=true`) seeds demo users + catalog, **no RBAC rows**.
- Plugin `populate_db.py` scripts seed plans/CMS, **no access levels**.

Consequence: the admin **User Edit → Access Levels** block (reads `vbwd_role`) and **User Access Levels** block (reads `vbwd_user_access_level`) render empty and hide themselves (the loaders `catch {}` silently). See report [`04`-style diagnosis in this session].

**Decision (2026-05-29):** default roles + permissions are **foundational data** (every instance, prod included) and must be created **as part of DB provisioning / the core seeder** — never as a `create_admin.py` side effect. The full role + permission-access-level set must be **import/exportable**.

## 2. Goal

1. **Core seeds the default roles + permissions** idempotently, on an **ungated** path that runs at DB provisioning + via the core seeder call (not behind `TEST_DATA_SEED`). The 3 roles mirror the existing `UserRole` enum — **no new roles invented** (no "manager").
2. **`create_admin.py` stops creating/owning roles** — it relies on the seeded roles (assigns the seeded `admin`/`super_admin` role and/or sets the enum). The enum-only fallback is removed.
3. **Import/export works for the seeded defaults** — roles AND user access levels round-trip through the existing `/admin/access/{import,export}` + `/admin/access/user-levels/{import,export}` endpoints (already present; this sprint pins them with tests + a canonical export fixture).
4. **Subscription plugin seeds 2 plan-linked user access levels** (`basic`, `pro`) via `UserAccessLevelService`, idempotently, in its `populate_db.py` (the script `deploy.sh --seed` already runs).

Net: a fresh instance (or a `make`/CLI call locally) has the canonical roles, permissions, and the basic/pro user access levels — both User-Edit blocks populate, and an operator can export the config from one instance and import into another.

## 3. Design

### 3.1 Core RBAC seeder — `vbwd/services/rbac_seeder.py` (NEW), ungated + idempotent

A single idempotent function (the **one home** — DRY) reused by the CLI, deploy, and tests:

```python
def seed_default_rbac(session, *, plugin_manager=None) -> RbacSeedResult:
    """Idempotently sync the permission catalog and upsert the 3 default
    system roles. Safe to re-run. Reads the catalog via DI (plugin_manager),
    never importing a plugin module — core stays agnostic."""
```

Steps:
1. **Sync the permission catalog → `vbwd_permission`.** Source = `CORE_PERMISSIONS` (in `vbwd/routes/admin/access.py`) + each enabled plugin's `admin_permissions` attribute, collected exactly like the existing `_get_all_permissions()` (extract that collector into a shared helper so the route + seeder share one source — DRY). Upsert each permission by `name` (`is_system` permissions are not deleted on re-run).
2. **Upsert 3 default `vbwd_role` rows** (`is_system=True`, by `slug`; never overwrite a non-system role of the same slug):
   - `super_admin` → permission **`*`** (wildcard; `Role.has_permission` already special-cases `*`).
   - `admin` → all CORE_PERMISSIONS (or `*` — **OPEN Q1**).
   - `user` → no admin permissions (empty / `[]`).
3. Return counts for logging.

Exposed as a CLI: **`flask seed-rbac`** (core, ungated — NOT behind `TEST_DATA_SEED`). Wired in `vbwd/app.py` `app.cli.add_command(...)`.

**Why a sync function, not a data migration:** the permission catalog evolves as plugins are added/enabled; a frozen Alembic data-migration would drift. The migration keeps creating the *tables* (already does); the seeder syncs the *content* idempotently on every deploy. (**OPEN Q2** — confirm vs a migration.)

### 3.2 `bin/create_admin.py` — stop owning roles

- Remove the enum-only fallback as the *role source*. After ensuring the user exists + is active, **assign the seeded granular role** (`super_admin`) via `RbacService.assign_role` (or keep setting the enum AND assign the role — **OPEN Q4**). If the seeded roles are absent, call `seed_default_rbac` first (so the script is self-sufficient on a fresh box) — i.e., create_admin *depends on* the seeder, doesn't *replace* it.

### 3.3 Provisioning wiring (`vbwd-demo-instances/deploy.sh` + recipe)

- Run `flask seed-rbac` **unconditionally** (every deploy, ungated) right after `flask db upgrade`, before `create-admin`. (`flask seed-test-data` stays gated for demo data.)
- Optional dev convenience: a `make seed-rbac` target in `vbwd-backend/Makefile` (**OPEN Q5** — Makefile is core; acceptable since it's a one-liner CLI invocation, not plugin coupling).

### 3.4 Import/export round-trip (already exists — pin it)

- `/admin/access/{export,import}` (roles) and `/admin/access/user-levels/{export,import}` are present. Add tests proving: seed → export → wipe non-system → import → identical set; and that **system roles are not overwritten** on import (existing `import_access` guard). Ship a canonical `docs/.../default-rbac.export.json` fixture (the exported default set) for operators.

### 3.5 Subscription `populate_db.py` — 2 plan-linked user access levels

- In `plugins/subscription/populate_db.py` (the script `deploy.sh --seed` runs), after plans exist, idempotently create `vbwd_user_access_level` rows for **`basic`** + **`pro`** (`linked_plan_slug`) via **`UserAccessLevelService`** (through the service — no raw SQL). Re-run = no-op. The existing `access_level_handler` then assigns these on `subscription.activated`.
- Lives entirely in the subscription plugin (gnostic). Core's seeder does NOT know about plans.

## 4. TDD plan (RED first)

**Core — `tests/unit/services/test_rbac_seeder.py` (NEW, ≥ 8):**
1. seeds 3 roles with correct slugs + `is_system=True`.
2. `super_admin` has `*`; `admin` has all CORE_PERMISSIONS; `user` has none.
3. permission catalog synced — every CORE_PERMISSIONS key exists as a `vbwd_permission` row.
4. plugin `admin_permissions` synced when a fake plugin is registered in the injected `plugin_manager` (DI; no plugin import).
5. **idempotent** — second run creates 0 new roles/permissions.
6. does NOT overwrite a pre-existing non-system role of the same slug (Liskov on the import guard).
7. catalog collector is the shared helper (route + seeder return the same set — DRY).
8. fail-fast on a malformed catalog entry.

**Core — `tests/unit/test_create_admin.py` (extend/new):** create_admin assigns the seeded `super_admin` role; calls the seeder when roles are absent; no longer the sole role source.

**Core — import/export round-trip** `tests/integration/.../test_rbac_import_export.py` (≥ 3): export-after-seed shape; wipe-non-system + import = identical; system roles untouched on import.

**Subscription — `plugins/subscription/tests/.../test_populate_access_levels.py` (≥ 3):** creates basic + pro user access levels with correct `linked_plan_slug`; idempotent re-run; goes through `UserAccessLevelService` (mock asserts).

## 5. Files

| Action | Path |
|---|---|
| new | `vbwd/services/rbac_seeder.py` — `seed_default_rbac` + `RbacSeedResult` |
| new | `vbwd/cli/seed_rbac.py` — `flask seed-rbac` (ungated) |
| edit | `vbwd/routes/admin/access.py` — extract catalog collector helper (shared with seeder) |
| edit | `vbwd/app.py` — register `seed-rbac` CLI |
| edit | `bin/create_admin.py` — assign seeded role; drop enum-only role ownership |
| edit | `plugins/subscription/populate_db.py` — seed basic+pro user access levels via service |
| new | tests (core unit + integration; subscription unit) per §4 |
| edit | `vbwd-demo-instances/deploy.sh` — run `flask seed-rbac` unconditionally post-migrate |
| new | canonical `default-rbac.export.json` fixture |

## 6. Acceptance

- Fresh DB + `flask db upgrade` + `flask seed-rbac` → `vbwd_role` has super_admin/admin/user; `vbwd_permission` has the full core catalog; re-run is a no-op.
- `deploy.sh --seed` on a fresh instance → both User-Edit blocks populate (roles for an ADMIN user; basic/pro user access levels).
- `create_admin.py` on a fresh box yields an admin holding the granular `super_admin` role (not just the enum).
- Export → wipe non-system → import reproduces the set; system roles not overwritten.
- `bin/pre-commit-check.sh --full` GREEN (core) + `--plugin subscription` GREEN.

## 7. Out of scope

- New permission *keys* beyond today's `CORE_PERMISSIONS` + plugin `admin_permissions`.
- A "manager" or any role beyond the 3 enum-aligned ones.
- fe-admin UX change (the silent `catch {}` in `UserEdit.vue` that hides the block on load error) — **OPEN Q6**: fold a small "surface load errors" fix in, or separate sprint?
- Migrating historic instances' existing manually-created roles.

## 8. Decisions (negotiated 2026-05-29 — LOCKED)

- **Q1 → all CORE_PERMISSIONS.** `super_admin` = `*`; `admin` = the 8 explicit core perms; `user` = none. Future plugin perms are NOT auto-granted to `admin`.
- **Q2 → ungated `flask seed-rbac` run on every deploy** (after `flask db upgrade`, before create-admin). Idempotent sync, not a data migration.
- **Q3 → NO app-bootstrap auto-run.** Explicit CLI only (+ `make seed-rbac` for dev). Avoids per-test/boot overhead.
- **Q4 → assign granular role AND keep the enum** (belt-and-suspenders during transition; both gating paths agree).
- **Q5 → YES**, add a `make seed-rbac` convenience target to the core Makefile.
- **Q6 → subscription-only (basic + pro).** Core seeds roles/permissions only; no core base user access level. Cleanest agnostic split.
- **Q7 → SEPARATE sprint.** The fe-admin `UserEdit.vue` silent-`catch {}` fix (surface load errors instead of hiding the block) is out of scope here; this sprint is backend RBAC seeding only.

## 8b. Addendum (2026-05-29) — foundational COUNTRIES seeding

Same "foundational reference data, seeded by default, ungated, idempotent" pattern as RBAC. The ~72-country list + `ENABLED_CODES={DE,AT,CH,FR,IT,PL,ES,TH}` (DACH must be enabled — `test_admin_countries.test_list_includes_dach_enabled`) currently lives **inline in the gated `bin/install_demo_data.py`** (lines ~467-518), so a non-demo instance has 0 countries (the `/admin/settings` country list is empty).

- **Extract** the list + seed logic into `vbwd/services/country_seeder.py` → `seed_countries(session) -> CountrySeedResult` (upsert by `code`, idempotent; `is_enabled` + `position` per `ENABLED_CODES`).
- **`flask seed-countries`** CLI (ungated), registered in `app.py`, wired into `deploy.sh` next to `seed-rbac`.
- **`bin/install_demo_data.py`** uses the extracted `seed_countries()` (DRY — single source; remove the inline copy).
- Tests: seeds all countries; DACH enabled; idempotent re-run; install_demo_data delegates to the shared seeder.

## 9. Engineering-requirements check

- **TDD-first:** ≥ 14 specs land RED before the seeder body.
- **DevOps-first:** ungated, idempotent, runs local + CI from cold start; no raw SQL; tables via existing migration.
- **SOLID/DI:** seeder reads the catalog via the injected `plugin_manager` (no plugin import — core agnostic); roles/permissions created via repos/services.
- **DRY:** one catalog collector shared by the `/permissions` route + the seeder; one `seed_default_rbac` reused by CLI + deploy + create_admin + tests.
- **Liskov:** import never overwrites system roles; re-run is a no-op (idempotent contract).
- **NO OVERENGINEERING:** reuse the existing import/export + RoleRepository + UserAccessLevelService; no new RBAC framework; 3 roles only.
- **Core agnostic:** core seeds core roles/permissions + syncs plugin permissions via DI; subscription seeds its own plan-linked access levels.
