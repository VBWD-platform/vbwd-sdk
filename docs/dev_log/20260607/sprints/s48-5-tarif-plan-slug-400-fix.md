# S48.5 — Fix `GET /api/v1/tarif-plans/<slug>` 400 BAD REQUEST (100% failing)

**Status:** PLANNED — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-backend` `plugins/subscription` (`subscription/routes/user_plans.py` + pricing/currency/tax services). **Correctness bug — load-independent.**

## Engineering requirements (BINDING)

TDD-first · SOLID · DI · DRY · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin subscription --full` green. No raw SQL ([[feedback_migrations_only]]); seed/demo data through services ([[feedback_no_direct_db_for_test_data]]).

## Problem (measured)

In every heavy-load run (50, 100, 500 VU) `GET /api/v1/tarif-plans/<slug>` fails **100%** (e.g. 441/441 at 100 VU) — alone ~83% of the whole error rate. The failure is **`400 BAD REQUEST`** (refined from the earlier "likely 500" guess via the 500-VU log). The **list** endpoint `GET /api/v1/tarif-plans` succeeds at 9 ms; only the **detail** route fails. The detail route additionally runs **currency + tax pricing resolution** (`CurrencyService` / `TaxService`) the list does not — the prime suspect.

The Locust scenario calls it with a real slug from the list payload and **no query params**: `GET /api/v1/tarif-plans/{slug}`. The route docstring shows `?currency=USD&country=DE` and the code defaults `currency=EUR`, `country=None` — so a missing param should *not* 400. The 400 therefore comes from **inside pricing resolution** (e.g. no active `EUR` currency / FX rate seeded, an unsupported currency, or a tax-resolution validation), not from request validation.

## Goal

`GET /api/v1/tarif-plans/<slug>` returns **200 with pricing** for every plan the list endpoint returns, on the same seeded data the load test uses — driving the harness's `/tarif-plans/<slug>` failure count to ~0.

## Investigation → fix (TDD-first)

1. **Reproduce locally** against the same seed: `flask seed all` (S30) on a fresh DB, then `curl /api/v1/tarif-plans` → take a real slug → `curl /api/v1/tarif-plans/<slug>` and capture the exact 400 body + the server traceback (the `400` JSON `{"error": …}` will name the failing branch).
2. **Write a failing integration test** (`plugins/subscription/tests/integration/…`): seed a plan + the currency/tax fixtures the demo seed creates, `GET /api/v1/tarif-plans/<slug>` (no params, and with `?currency=USD`) → assert **200** + a priced body. RED first.
3. **Root-cause within pricing resolution.** Most likely one of:
   - the demo seed doesn't create the default `EUR` currency / FX rate the detail route requires → `CurrencyService` raises → 400. Fix: make the seed create the baseline currency (through the service), and/or make pricing fall back gracefully when a rate is absent.
   - a tax-resolution path 400s when `country` is None → make country optional end-to-end (the docstring says it is).
   - an unhandled `ValueError` mapped to 400. Fix: handle the specific missing-data case explicitly (clear 404/422 only when genuinely not found, else 200 priced).
4. **Narrowest fix** at the proven layer (seed data vs service fallback vs route) — make the failing test green without widening scope.

## Acceptance

- New integration test(s) green; the 400 path is covered by a regression test pinned to seeded data.
- `--plugin subscription --full` green.
- Manual: on a `flask seed all` DB, every slug from `/tarif-plans` returns 200 from the detail route.
- Re-dispatch heavy load (100 VU): `/tarif-plans/<slug>` failure count ≈ 0; aggregate error% drops from ~6% to ~1%.

## Out of scope

- Pricing/FX feature changes beyond making the existing path resolve on seeded data.
- Caching the detail route (that's S48.2 territory if it proves hot).
