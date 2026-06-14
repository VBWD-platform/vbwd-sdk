# S88 — `flask reset-demo` as the single complete demo-seed entrypoint

> Binding engineering requirements (restated; canonical
> `docs/dev_log/20260525/sprints/_engineering-requirements.md`, local anchor
> [`_engineering_requirements.md`](./_engineering_requirements.md)):
> **TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code ·
> NO OVERENGINEERING**, guarded by `bin/pre-commit-check.sh`
> (`--full` green on every touched repo = done; `--quick` while iterating).

## Problem (verified broken state)

`flask reset-demo --yes` (→ `vbwd/cli/reset_demo.py` → `vbwd/cli/_demo_seeder.py`
`DemoSeeder.run()`) is fragmented and crashes:

1. **Crash.** `_clear_transactional_data()` does a bare `DELETE FROM
   token_transaction` (etc.); when a plugin's table is not migrated/present the
   reset aborts with `relation "token_transaction" does not exist`.
2. **Incomplete.** Only the `subscription` plugin registers a catalog seeder via
   `demo_data_registry`. reset-demo therefore seeds core token bundles +
   countries + subscription plans/addons, but NOT shop products, booking
   resources, ghrm software, any CMS pages/widgets/layouts, and never runs
   `flask cms backfill`.
3. **Inconsistent invocation.** Each plugin has its own populate entrypoint with
   different invocation conventions (`populate_db.py`, `bin/run_populate.py`,
   `src/bin/populate_*.py`). The single-command demo seed must orchestrate them
   all.

## Goal

`flask reset-demo --yes` produces the COMPLETE demo DB in one command:
all core data + every feature plugin's catalog + all CMS pages/widgets/layouts +
`cms backfill`, equal to manually running each plugin populate + backfill. Key
CMS pages resolve via `GET /api/v1/cms/posts/<slug>?type=page`.

## Design (core stays plugin-agnostic)

- **Clear-step robustness.** Guard every transactional/catalog `DELETE` with
  `inspector.has_table(...)` — skip absent tables (no bare `except`).
- **Registry indirection (DIP / O).** Each feature plugin registers its catalog
  seeder hook into `vbwd/services/demo_data_registry.py` from `on_enable`
  (mirrors `subscription`). Core imports no plugin model.
- **DRY seed logic.** Each plugin grows a `seed_catalog(session)` (session-taking,
  idempotent upsert). The standalone `populate*` scripts become thin wrappers
  over that single function.
- **CMS pages + backfill ordering.** A new `post_seed` hook category in the
  registry runs AFTER all catalog seeders. cms registers the backfill there.
  Order: core bundles/countries → catalog seeders (incl. cms pages/widgets) →
  post-seed (cms backfill). The backfill is invoked through
  `CmsBackfillService` directly (not a shell subprocess).
- **Summary.** reset-demo prints the extended stats (plans/products/resources/
  software/pages/widgets/layouts + backfill copied).

## RED tests (write first)

Backend (`tests/unit/cli/test_reset_demo_seeder.py`, integration variant):
- `_clear_transactional_data` is a no-op for an absent table (simulate missing
  table) — not a crash. (regression for the verified crash)
- `run_catalog_seeders(session)` invokes every registered hook; with no hook
  registered (plugin disabled) it is a no-op (Liskov / agnostic).
- `run_post_seed_hooks(session)` invokes registered post-seed hooks; no-op when
  none.
- E2E (integration, throwaway DB): after `DemoSeeder.run()` + cms backfill, ≥1
  shop product, ≥1 booking resource, ≥1 ghrm package, ≥1 tarif plan, ≥1 token
  bundle exist AND key CMS pages resolve as `cms_post` (`shop`, `booking`,
  `shop-cart`, `checkout-confirmation`, `ghrm-software-catalogue`).
- Idempotency: `DemoSeeder.run()` twice does not error or duplicate.
- Per-plugin: each `seed_catalog(session)` unit test (idempotent upsert).

## What we deliberately do NOT build

- No new landing pages (`/tarifs`, `/addons`, `/soft`) — separate follow-up.
- No new abstraction layer beyond the existing registry; reuse it.
- No change to the `flask seed` command (S30) — reset-demo is the orchestrator.
- No Swift/iOS.

## Gate

`--quick` while iterating; before done: live `flask reset-demo --yes` in the
`api` container + verify 5 vertical APIs 200 + `GET /api/v1/cms/posts/shop?type=page`;
`bin/pre-commit-check.sh --plugin {subscription,shop,booking} --full` green +
core black/flake8/mypy on touched files + core unit + new reset-demo tests green.
