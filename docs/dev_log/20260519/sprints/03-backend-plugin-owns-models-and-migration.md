> **⚠ SUPERSEDED — replaced by
> [`03-merged-decouple-core-and-relocate-subscription.md`](../done/03-merged-decouple-core-and-relocate-subscription.md)**
> (merged with Sprint 04 per report 02 §3a R1). The Baseline (E1) section
> here is done & still valid; the rest is history. Execute from the merged
> doc.

# Sprint 03 — Backend: plugin owns models + its own migration

**Phase:** 1 · **Repos:** `vbwd-backend`, `vbwd-backend/plugins/subscription`
**Effort:** L (~3–5 dev-days) ⚠ highest-risk sprint · **Depends on:** 01
**Blocks:** 04 · **Engineering requirements:** [`_engineering-requirements.md`](./_engineering-requirements.md) — binding (esp. **E4**).

## Goal

Make the subscription plugin the **sole owner** of its 5 model classes and
its database schema. Today core owns the models and the monolithic migration
`alembic/versions/20260403_1612_vbwd_all_tables.py` creates the subscription
tables; the plugin only re-exports (`subscription/models/__init__.py` shim).

End state: `import vbwd.models.subscription` ⇒ `ModuleNotFoundError`; the
plugin defines the models and ships its own Alembic branch; **existing prod
data is preserved** (adopt, not drop+recreate — E4).

## Models in scope

`Subscription`, `TarifPlan`, `AddOn` (+ `addon_tarif_plans` m2m),
`AddOnSubscription`, `TarifPlanCategory` (+ `tarif_plan_category_plans` m2m).

## Baseline (E1)

1. Integration characterisation test against current (core-owned) models:
   `plugins/subscription/tests/integration/test_schema_characterisation.py`
   - records, via the `db` fixture, the live DDL fingerprint: table names,
     columns, types, nullability, FKs, indexes, m2m tables — asserted as a
     frozen snapshot dict. Run GREEN on `main` first.
2. Repository round-trip char test: create→read→update→delete each entity
   through the **plugin** repositories (which today proxy core models). GREEN
   on `main`.
3. `flask db heads` / `flask db history` output recorded (current single core
   head including the monolith).

These two tests, unchanged, must be GREEN after the move (E2).

## Failure / architecture analysis

Report §3.1(a) + §4.2/4.3: the plugin re-export shim
(`plugins/subscription/subscription/models/__init__.py:6-13`) exists *only*
because moving the model code was punted to a never-scheduled "Phase 2". A
booking-only install therefore still defines + migrates the whole subscription
schema — the original motivation (report §1) is unmet. No plugin migration
exists; schema lives in the 2026-04-03 core monolith.

## ⚠ Refinement R1 (discovered during Baseline — binding)

Implementation found **11 core (non-plugin) files** still hard-import the 5
model modules: `vbwd/repositories/{subscription,tarif_plan,tarif_plan_category,
addon,addon_subscription}_repository.py`, `vbwd/services/{subscription,
tarif_plan,tarif_plan_category}_service.py`, `vbwd/plugins/
payment_route_helpers.py`, `vbwd/models/invoice_line_item.py`, plus the
seeders. **Removing those importers is Sprint 04's scope, and Sprint 04 runs
*after* Sprint 03** (README dependency graph). A hard delete of
`vbwd/models/subscription.py` here would raise `ModuleNotFoundError` across
core at import time → whole backend/test-suite fails → gross E2 violation.

> **SUPERSEDED — see [`../reports/02-...md`](../reports/02-phase0-outcome-and-locked-decisions.md)
> §3a (R1 conclusion).** The "inverted shim" sketched below was **rejected**:
> core re-export stubs would force core to import the plugin package at
> startup (worse agnosticism violation + cycle risk). **Binding conclusion:
> Sprint 04 must run before Sprint 03** (or merge) — remove core's 11
> subscription importers first, then the model move is clean with no shim.
> This is a programme re-sequencing, paused for an explicit decision. The
> Baseline (E1) below is done & valid regardless. Ignore the inverted-shim
> wording in step 1; it is retained only for history.

Therefore Sprint 03's "`import vbwd.models.subscription` ⇒
ModuleNotFoundError" acceptance is **deferred to the end of Sprint 04** and
this sprint instead does the **inverted shim**:

- The **plugin becomes the definition site** for the 5 models.
- Core `vbwd/models/{subscription,…}.py` become **thin re-exports** from the
  plugin (`from plugins.subscription.subscription.models.subscription import
  Subscription`), so the 11 still-present core importers keep working
  **unchanged** (E2: zero behaviour change, full suite stays green).
- `vbwd/models/__init__.py` keeps its names (now sourced via the re-export).
- The plugin `subscription/models/__init__.py` shim is **inverted**: it
  stops importing from `vbwd.models.*` and defines the classes locally.

The hard `ModuleNotFoundError` cut + deleting the core re-export files
becomes the **final step of Sprint 04**, once the 11 importers are gone.
Sprint 03 is also split: **03a = this model move (inverted shim)**;
**03b = the Alembic migration (step 3 below)**, which additionally requires
the ops DB-backup/maintenance-window prerequisite and is run as its own
focused unit. Recorded in report 02 as Refinement R1.

## TDD plan (RED → GREEN, ordered)

1. **Move models (mechanical, behaviour-frozen; inverted shim per R1):**
   - New `plugins/subscription/subscription/models/{subscription,tarif_plan,addon,addon_subscription,tarif_plan_category}.py`
     containing the *verbatim* class bodies (same `__tablename__`, columns,
     `to_dict`, relationships) — E2: no field/behaviour change.
   - `subscription/models/__init__.py` stops re-exporting from `vbwd.models.*`
     and instead defines/exports them locally (imports the new modules).
   - Core `vbwd/models/{subscription,…}.py` become **re-export stubs** that
     import from the plugin (NOT deleted in 03a — R1). `vbwd/models/__init__`
     lines unchanged (still resolve, now via the stub).
   - **RED first:** `tests/integration/test_subscription_models_defined_in_plugin.py`
     asserting `Subscription.__module__` starts with
     `plugins.subscription.subscription.models` (definition site moved) while
     `from vbwd.models import Subscription` still works (re-export intact).
     Red now (still core-defined), green after the move.
   - Baseline repo round-trip char test must stay GREEN (proves model
     semantics unchanged through the relocation — the Liskov contract E2).
2. **SQLAlchemy registry / metadata:** the plugin models must register on the
   same `db.Model` metadata used by migrations. Add
   `tests/integration/test_plugin_models_in_metadata.py` — asserts the 5
   tables are present in `db.metadata.tables` **only when the plugin is
   enabled**, absent when disabled (drives the conditional import in the
   plugin's `__init__`/`models` loading). RED → implement conditional model
   registration → GREEN.
3. **Plugin Alembic branch (E4 — LOCKED by decision D2, report 02):**
   The subscription tables are **owned by the plugin migration**, not core.
   Core keeps only basic entities (`users`, `user_details`, `invoice`, token
   economy). Core's monolith `20260403_1612_vbwd_all_tables.py` must **stop
   creating** `vbwd_subscription` / `vbwd_tarif_plan` / `vbwd_addon*` /
   `vbwd_tarif_plan_category*` going forward.
   - Create `plugins/subscription/migrations/versions/` and register the path
     in `alembic.ini` `version_locations` (per
     `feedback_plugin_migrations_in_plugin.md`).
   - Plugin revision owns the 5 tables' DDL. **Data-preserving:** on an
     existing/prod DB it *adopts* the already-present tables (guarded no-op
     DDL — `op.execute` gated by table existence — plus a `branch_labels`/
     stamp so Alembic tracks them on the plugin branch); on a fresh DB it
     `create_table`s them; with the plugin disabled they are never created.
     It must **never drop** a populated table (E4).
   - Core companion revision: a guarded core migration that makes the
     monolith's subscription `create_table`s a **no-op when the tables are
     plugin-owned/already present**, so old DBs upgrading don't double-create
     and fresh core-only (plugin-disabled) DBs get **no** subscription tables.
     This replaces the earlier "leave monolith as-is" option — D2 requires
     core to relinquish ownership, not just stamp it.
   - Test `tests/integration/test_migration_fresh_and_existing.py`:
     - fresh DB + plugin enabled → `flask db upgrade` creates the 5 tables,
       DDL fingerprint == Baseline snapshot;
     - simulated "existing" DB (tables pre-created) → `upgrade` is a no-op,
       **zero rows lost**, fingerprint unchanged;
     - plugin disabled + fresh DB → subscription tables **absent**.
     RED → implement adoption migration → GREEN.
4. Baseline schema-characterisation + repo round-trip tests re-run GREEN
   unchanged (E2 gate).

## SOLID / DI / clean-code notes

- **S / O:** schema ownership follows feature ownership; new subscription
  columns are added by a plugin migration, never by editing a core file.
- **D (DIP):** core must not depend on subscription models. Any core code
  still importing them is *out of scope here by design* — it is Sprint 04's
  job; this sprint only proves core *package* no longer defines them.
- **Liskov (E2):** the repository round-trip char test is the substitution
  proof — same inputs/outputs/exceptions before and after the model move.
- **DRY:** kill the re-export shim entirely; one definition site.
- Clean code: model files keep full names, explicit `to_dict`, no flag args.

## Acceptance criteria

- `vbwd.models` defines none of the 5 models; `ModuleNotFoundError` test green.
- Plugin owns the models; Baseline char + round-trip tests GREEN unchanged.
- Plugin Alembic branch registered; fresh-DB upgrade builds the exact Baseline
  DDL fingerprint; existing-DB upgrade is a **non-destructive no-op**.
- Plugin-disabled fresh DB has **no** subscription tables.
- `make pre-commit` (lint + unit + integration) green.
- No raw SQL for data; no `# type: ignore` added without approval.

### E3 oracle slice made true

"`import vbwd.models.subscription` ⇒ ModuleNotFoundError" **and** "plugin-
disabled core migration creates zero `vbwd_subscription*`/`vbwd_tarif_plan*`/
`vbwd_addon*` tables".

## Risks ⚠

- **Prod data.** Drop+recreate would destroy live subscriptions/plans.
  Mitigation: adoption migration does zero DDL when tables exist; the
  existing-DB integration test asserts zero row loss; a prod run needs a
  backup + maintenance window (flagged to ops, **not** in this sprint's
  estimate).
- **Alembic multi-head.** Introducing a plugin branch off the monolith can
  create multiple heads. Mitigation: explicit `down_revision` /
  `branch_labels`; `test_migration_*` asserts `flask db heads` is
  single-or-correctly-branched; follow the established plugin-migration
  pattern (cms plugin precedent).
- **Metadata import order.** Models must load before `db.create_all`/migration
  autogen. Mitigation: conditional registration test (#2) pins the contract.

## Decisions (LOCKED — report 02 §3)

- **D2:** subscription schema is **plugin-owned** (plugin migration), core
  monolith relinquishes it via a guarded core companion revision; existing
  prod data is adopted, never dropped. No longer an open question.
- Remaining kickoff detail (mechanics, not direction): exact guard predicate
  for the core companion revision (`has_table` inspector check vs Alembic
  branch dependency) — chosen in the PR with the migration test matrix; does
  not change scope.
- Prod roll-out needs a DB backup + maintenance window — an **ops task**,
  tracked separately, outside this sprint's estimate.

## Effort

L — ~4–5 dev-days (D2 requires both the plugin migration **and** the guarded
core companion revision + the fresh/existing/disabled migration test matrix;
upper end of the original range).
