# Sprint 03 (merged 03+04) — Decouple core from subscription, then relocate models + schema

**Phase:** 1 · **Repos:** `vbwd-backend`, `vbwd-backend/plugins/subscription`
**Effort:** XL (~7–9 dev-days) ⚠ largest sprint · **Depends on:** 01
**Blocks:** 09 · **Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding.
**Authoritative re-baseline:** [`../reports/02-phase0-outcome-and-locked-decisions.md`](../reports/02-phase0-outcome-and-locked-decisions.md)
(decisions D2/D3, refinement R1). **This doc supersedes
`03-backend-plugin-owns-models-and-migration.md` and
`04-backend-break-live-couplings.md`** (kept for history only).

## Why merged

R1 proved the model relocation **cannot precede** removing core's
subscription importers, and a shim makes core import the plugin package on
startup (worse). Decision: **one sprint** that removes every core→subscription
dependency *first*, then relocates the models with **no shim**, then moves the
schema. Single dependency-ordered review.

## End state (the oracle this sprint must make true — E3)

- No `vbwd/**` file imports `vbwd.models.{subscription,tarif_plan,addon,
  addon_subscription,tarif_plan_category}` or the 5 subscription repos/services.
- `import vbwd.models.subscription` ⇒ `ModuleNotFoundError`; the 5 models are
  defined **only** in `plugins/subscription/subscription/models/`.
- Core serves no `/checkout` / `/addons`; `container.py` has no subscription
  factories; `FeatureGuard` gone from core; `invoice_line_item` has no
  subscription branch.
- Subscription schema is created by a **plugin** Alembic migration; core
  migrations create none of it; plugin-disabled fresh DB has zero
  `vbwd_subscription*` / `vbwd_tarif_plan*` / `vbwd_addon*` tables.
- Full backend suite green throughout (E2 — every step behaviour-preserving).

## Baseline (E1) — DONE

- `plugins/subscription/tests/integration/test_schema_characterisation.py`
  golden snapshot captured & stable; repo round-trip smoke green;
  `alembic heads` = `20260424_1015`. These stay GREEN unchanged at every step.
- Add, before any change, characterisation tests pinning the live behaviour
  of each coupling to be moved (per E1): `/checkout` + `/addons` (status,
  body, emitted event via spy dispatcher), `FeatureGuard` allow/deny matrix,
  `invoice_line_item._resolve_catalog_item_id` for SUBSCRIPTION/ADD_ON/
  TOKEN_BUNDLE, and a seeded-demo-data smoke. GREEN on `main` first.

## Work breakdown — strict dependency order (each slice: RED → GREEN → suite green)

> Rule: after **every** slice the full `make test` count stays ≥ the running
> baseline (live behaviour preserved; only tests of *removed* dead code may
> drop, and only with the plugin owning the live equivalent — Sprint 01
> precedent, documented per slice).

### S1 — `invoice_line_item` resolution via the registry (E6)
Core `vbwd/models/invoice_line_item.py:45-63` hard-imports subscription
models. Extend the existing line-item handler registry with
`resolve_catalog_item_id(line_item)`; plugin registers a subscription
resolver; core delegates with a null-object default (TOKEN_BUNDLE stays core).
RED: plugin resolver spec + core "no transitive subscription import" spec
(`sys.modules` clean after `import vbwd.models.invoice_line_item`). Baseline
`invoice_line_item` char test GREEN unchanged.

### S2 — `/checkout` + `/addons` → plugin blueprint
Move the route bodies from core `vbwd/routes/user.py` into the plugin
blueprint (verbatim handlers). Remove from `user_bp`. RED: plugin route char
tests; GREEN: Baseline `/checkout` `/addons` char tests unchanged (same URLs,
served by plugin — assert by blueprint name); core test `user_bp` exposes no
checkout/addons rule.

### S3 — `FeatureGuard` → plugin behind `IEntitlementProvider` (E6, D3)
Define narrow core port `IEntitlementProvider.is_feature_allowed(user_id,
feature_key) -> bool` (no subscription vocabulary). Plugin implements
`SubscriptionEntitlementProvider` (wraps old FeatureGuard +
SubscriptionRepository) and registers it. **D3:** absent provider ⇒ a core
config flag, **default allow** (test both flag states + provider-present
path). Delete `vbwd/services/feature_guard.py`. Baseline FeatureGuard char
test re-pointed at the port, GREEN unchanged.

### S4 — Core subscription repositories + services removed
With S1–S3 done, the core 5 subscription repos
(`vbwd/repositories/{subscription,tarif_plan,tarif_plan_category,addon,
addon_subscription}_repository.py`) and 3 services
(`vbwd/services/{subscription,tarif_plan,tarif_plan_category}_service.py`)
have no remaining core caller (the plugin already ships its own). RED: a
guard test asserting core has no subscription repo/service module
(`importlib.util.find_spec` is None) + suite count rule. Delete them + their
`__init__` exports + the subscription factories/docstring in
`vbwd/container.py` (D-decision: container exposes no subscription factory).
Also `vbwd/plugins/payment_route_helpers.py` subscription imports →
relocate/guard (it is plugin-support glue; move into plugin or behind the
registry — decided in slice kickoff).

### S5 — Seeders
`vbwd/testing/test_data_seeder.py` + `vbwd/cli/_demo_seeder.py` import
subscription models. Route subscription demo/test data through the **plugin's**
seeder (`plugins/subscription/populate_db.py`) and have the core seeder call
the plugin's only when the plugin is enabled (no raw SQL —
`feedback_no_direct_db_for_test_data.md`). RED: plugin-disabled seeder smoke
(core seeds users/invoices/tokens, no subscription) + plugin-enabled smoke
(subscription rows present). Baseline demo-data smoke GREEN unchanged.

### S6 — Relocate the 5 models (NO shim — R1)
Now zero `vbwd/**` files import the subscription models. Move the verbatim
class bodies into `plugins/subscription/subscription/models/{...}.py`; invert
`subscription/models/__init__.py` to define locally; **delete** core
`vbwd/models/{subscription,tarif_plan,addon,addon_subscription,
tarif_plan_category}.py` and their `vbwd/models/__init__.py` lines. RED:
`test_core_has_no_subscription_models` — `import vbwd.models.subscription`
⇒ `ModuleNotFoundError`, `vbwd.models.__init__` exposes none of the 5.
Baseline schema fingerprint + repo round-trip GREEN **unchanged** (E2 — the
relocation Liskov proof).

### S7 (= 03b) — Plugin owns the schema (D2) — code now, prod run later
- `plugins/subscription/migrations/versions/` registered in `alembic.ini`
  `version_locations` (`feedback_plugin_migrations_in_plugin.md`).
- Plugin revision owns the 5 tables + 2 m2m DDL. **Data-preserving:** on a
  DB that already has the tables (prod) it adopts (guarded no-op DDL via
  `inspector.has_table`, plus branch/stamp); fresh DB creates; plugin
  disabled never creates. Never drops a populated table (E4).
- Guarded **core companion revision** makes the monolith
  `20260403_1612_vbwd_all_tables.py` subscription `create_table`s a no-op
  when the tables exist / are plugin-owned, so old DBs don't double-create
  and core-only fresh DBs get none.
- Tests: `test_migration_fresh_and_existing` — (fresh+enabled → 7 tables,
  fingerprint == Baseline snapshot), (existing → no-op, **zero rows lost**),
  (disabled+fresh → tables absent). All GREEN.
- **Prod execution is NOT performed by this sprint.** Per your decision:
  code + full fresh/existing/disabled test matrix land now; the prod upgrade
  is run by you after a DB backup + maintenance window. The sprint ships a
  short `RUNBOOK` section (backup cmd, upgrade cmd, rollback = restore
  backup; the migration itself never drops).

## SOLID / DI / clean-code (applies to every slice)

- **DIP:** core depends on the line-item registry + `IEntitlementProvider`
  *abstractions*; the plugin supplies concretions. Arrow points plugin→core
  abstractions only; never core→plugin package.
- **ISP:** `IEntitlementProvider` is one method; line-item registry one added
  method. No fat ports.
- **OCP/SRP:** adding/removing subscription = registrations + plugin
  enable/disable, never editing a core branch.
- **Liskov/E2:** each Baseline char test is the per-slice substitution proof;
  none may be edited to pass. Behaviour identical at the new call site.
- **DRY:** one entitlement port, one line-item registry, one subscription
  seeder (plugin's). Kill the core duplicates, don't fork them.
- Clean code: full names, no flag args, zero "what" comments, no
  `# type: ignore`/`# noqa` without approval.

## Acceptance criteria

- The §"End state" oracle holds; `make pre-commit` (lint+unit+integration)
  green; Baseline snapshot + all per-slice char tests GREEN **unchanged**.
- Plugin-disabled backend boots, serves all non-subscription routes, creates
  zero subscription tables, evaluates no subscription gating (D3 allow).
- 03b: fresh/existing/disabled migration matrix GREEN; RUNBOOK present;
  **prod not executed** (handed to ops).

### E3 oracle slice made true

The entire backend slice of the agnosticism oracle (Sprint 09 automates it).

## Risks ⚠

- Hidden core importer missed → `ModuleNotFoundError` at S6. Mitigation: the
  `sys.modules`/`find_spec` guard tests at S1–S4 make every edge visible
  *before* S6; S6 only proceeds when the guard suite is green.
- Behaviour drift moving routes/guard. Mitigation: spy-dispatcher + matrix
  Baseline char tests pin event names/payloads and allow/deny exactly.
- Migration data loss. Mitigation: adopt-not-recreate, `has_table` guards,
  existing-DB zero-row-loss test, prod gated behind your backup/window.

## Status

Baseline (E1) **done**. Implementation proceeds S1→S7 in order; each slice is
a separate atomic change with its own RED→GREEN and a green full suite before
the next.
