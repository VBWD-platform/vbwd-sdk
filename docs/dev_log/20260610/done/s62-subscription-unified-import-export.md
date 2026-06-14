# S62 — Subscription → unified import/export

**Plugin:** `subscription` · **Depends on:** core data-exchange framework · **Blocks:** S63, S65
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering;
`bin/pre-commit-check.sh --plugin subscription --full` green = done. See the overview +
`_engineering-requirements.md`.

> **Reconciliation (2026-06-10, verified):** S46 already shipped `subscription_plans` and
> `subscription_addons` (in the existing `subscription_exchangers.py`). **Two gaps:** (1) there is
> **no `subscription_categories` exchanger** for `TarifPlanCategory`; (2) the existing plans/addons
> exchangers carry **no slug-links** (a transported plan loses its category, an addon loses its
> plans). ⚠️ `fk_natural_key_map` is **export-only** — links must be resolved on import by a thin
> subclass. So this sprint **adds one exchanger and upgrades two existing ones**, not greenfield.

## Problem
A new instance's plan catalogue can't be seeded as a connected graph: plan **categories** aren't
exchangeable at all, and the existing plan/addon exchangers export no category/plan links — so an
imported plan is orphaned from its category and an addon from its plans.

## Goal
**Add** a `subscription_categories` exchanger (`TarifPlanCategory`), and **upgrade** the existing
`subscription_plans` to carry `category_slugs` and `subscription_addons` to carry
`tarif_plan_slugs` — all links by **slug**, resolved on import via a thin subclass.

## Scope / exchangers
**Extend the existing** `plugins/subscription/subscription/services/data_exchange/subscription_exchangers.py`
(`build_subscription_exchangers(session)` already builds plans + addons; add the category exchanger
and convert plans/addons to link-carrying subclasses).

1. **`subscription_categories`** (`TarifPlanCategory`) — **NEW** (plain `BaseModelExchanger`, or a
   thin subclass if hierarchical):
   - `natural_key="slug"`, `cluster=CLUSTER_SALES`, label "Plan Categories".
   - `public_fields=[name, slug, description, sort_order, is_active, config?]` (per the model).
   - `parent_id` (if hierarchical): export-only via `fk_natural_key_map`; **resolve the parent slug
     on import in the subclass** (or keep flat + omit `parent_id`).
2. **`subscription_plans`** (`TarifPlan`) — **UPGRADE the existing exchanger** to a thin subclass
   (keep the `subscription_plans` entity key) — add the M2M category link:
   - `natural_key="slug"`, `cluster=CLUSTER_SALES`, label "Tarif Plans".
   - `public_fields=[name, slug, description, price, price_float, currency, billing_period,
     trial_days, features, is_active, sort_order, …]` (full serialisable set per `TarifPlan.to_dict`).
   - **Price**: export `price`/`price_float`/`currency` (the denormalised values). The internal
     `price_id` FK → `vbwd_price` is **not** exported/imported (instance-local pricing object);
     on import, set the denormalised fields only (note: if the runtime requires a `vbwd_price` row,
     create/resolve it from the denormalised values in the apply step — confirm in TDD).
   - **Categories M2M**: serialise `category_slugs: [slug,…]`; **resolve on import in the subclass**
     (skip-with-error on unknown slug — `fk_natural_key_map` won't do this).
3. **`subscription_addons`** (`Addon`) — **UPGRADE the existing exchanger** to a thin subclass
   (keep the `subscription_addons` entity key) — add the M2M `tarif_plans` link:
   - `natural_key="slug"` (add a slug if the model lacks one — check; else `natural_key` = name+unique
     or id with a documented caveat), `cluster=CLUSTER_SALES`, label "Add-ons".
   - `public_fields=[name, slug?, description, price, currency, config, is_active, …]`.
   - serialise `tarif_plan_slugs: [slug,…]` from the `addon_tarif_plans` M2M; resolve on import.

Register via `SubscriptionPlugin.on_enable` → add a `_register_data_exchangers()` hook (mirror
booking/cms) that calls `register_subscription_exchangers(db.session)`.

## TDD test plan (write first — `plugins/subscription/tests/unit/.../test_subscription_exchangers.py`)
- **Round-trip** each entity: create category + plan(in category) + addon(bound to plan) → export
  all three → import into a clean session → recreated with links resolved **by slug**; price,
  billing_period, features, trial_days preserved.
- **Plan↔category M2M** and **addon↔plan M2M** resolve by slug; unknown slug → error row, no crash.
- **Price**: `price_float`/`price`/`currency` preserved; if a `vbwd_price` row is created on import,
  assert it matches the denormalised values (or that import is price-id-agnostic).
- **Upsert** by slug (re-import → updated, not duplicated).
- **dry_run** → no writes. **Manifest/perms**: appear with `plans.view`/`plans.manage` (reuse the
  plan admin perms), hidden otherwise.
- **Import order independence within the envelope** (categories before plans before addons handled
  by the framework's section order; a plan referencing a not-yet-imported category in a single-entity
  import → error row).
- **Liskov**: export-then-import is a no-op on an unchanged DB (idempotent).

## fe-admin
- Confirm the three entities appear in the core `ImportExport.vue` (manifest-driven), Sales cluster.
  No per-plugin import view. (The existing `subscription-admin` plan/addon CRUD is unchanged.)

## Acceptance
- `--plugin subscription --full` green.
- Exporting a seeded plan catalogue and importing into an empty instance reproduces categories +
  plans + add-ons with all links; `/landing1` (or the plans listing) then renders them.

## Risks / notes
- The `price_id → vbwd_price` indirection is the main subtlety — resolve to a documented, tested
  rule (prefer importing the denormalised price; create/lookup the `vbwd_price` only if the booking/
  checkout runtime requires it). Confirm `Addon` has a stable natural key (add a `slug` migration
  **only if** required — that would be a small extra step, flag it). No change to subscription
  runtime logic.
