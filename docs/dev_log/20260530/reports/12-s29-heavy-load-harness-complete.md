# Report 12 — S29: heavy-load test harness fixes (workflow + Locust scenario)

**Date:** 2026-06-02
**Repo:** `vbwd-platform` (`tests/load/` + `.github/workflows/`).
**Status:** ✅ **Code complete & locally green** (15 harness unit specs). The
**final acceptance gate — a heavy-load workflow re-dispatch — is the user's to
pull**: it runs against `vbwd-platform`'s pushed `main`, so these changes must be
committed + pushed first, and a 50-VU CI run is billed/outward-facing. Not
committed, not dispatched (standing rule).

> **Note on numbering:** this sprint doc is filed `s30-heavy-load-harness-fixes.md`
> but internally titled **S29**; its companion `s30-load-test-code-affordances.md`
> is the backend S30 (report 11). Status.md now lists them as 29 (harness) / 30 (backend).

## Grounding correction (the doc was guessing the layout)

The sprint doc assumed `loadtest/scenarios/full.py` + `loadtest/thresholds.py`.
Reality: a single `tests/load/locustfile.py` with the threshold check inline, and
the file was **newer than report 04** — it already had per-VU `on_start` bearers
and f-string slugs. So I verified every endpoint against the live backend source
and found the *actual* drift (different from the doc's guesses):

| Scenario call (before) | Real backend contract | Fix |
|---|---|---|
| register `{email, password, name}` | `RegisterRequestSchema` raises on unknown fields → `400 Unknown field 'name'` | drop `name` → `{email, password}` |
| `GET /api/v1/user/token-balance` | core `user_bp` serves `/api/v1/user/tokens/balance` | path fix |
| `POST /api/v1/token-payment/quote` (JSON body) | token_payment plugin: `GET /api/v1/plugins/token-payment/quote?amount=&currency=` | method + path + query-params |
| admin `?page=1&per_page=20` | admin uses `limit`/`offset` | `?limit=20&offset=0` |

The register `name` bug was the **root of report 04's 401 wall**: it made every
`_register` return `None` → empty bearer → 401 on every authed scenario. Fixing
the payload fixes both the register 400 *and* the 401 cascade (Slice 1 + 2 in one).
The other scenario URLs (tarif-plans, addons, bundles, subscriptions/active,
user/addons, user/invoices, checkout, tarif-plans/<slug>) were verified **correct**.

## What shipped

**Slice 0 — workflow seed step** (`heavy-load.yml`): replaced the
`populate_db.py … || true` loop (which silently hid partial seeds — report 04's
other root cause) with S30's **`flask seed all`** (fail-fast, non-zero on any
plugin error) after `flask seed-test-data`. Added a **`/_seed_status`
completeness gate** that fails the job loudly if any plugin is left unseeded.
Enabled S30's debug endpoints in CI via a new compose env
`VBWD_ENABLE_DEBUG_ENDPOINTS` (default off; the workflow sets it to `1`).

**Slice 1/2 — locustfile** (`tests/load/locustfile.py`): the 4 contract fixes
above, plus a **pre-load contract smoke** (`@events.test_start`) that reads
`GET /api/v1/_routes` (S30) and fails fast on URL drift before any VU spawns —
gracefully skipped if the endpoint is unavailable (older backend / debug off).
`SCENARIO_ENDPOINTS` is the single source of truth the smoke checks.

**Slice 3 — typed thresholds** (`tests/load/thresholds.py`, NEW): extracted the
inline check into a pure `evaluate(stats) -> (exit_code, breaches)` with typed
categories (`error_pct`, `p95_ms`, `p99_ms`, `min_throughput_rps`) plus
`harness_smoke` preemption and a `no_data` guard (zero requests → distinct breach,
not a misleading `error_pct=0%`). Each breach prints one
`BREACH category=… actual=… budget=…` line. The locustfile's `quitting` listener
now delegates to it (the two legacy budgets stay env-overridable).

**Tests + CI:** `tests/load/tests/test_thresholds.py` (9) +
`test_scenario_units.py` (6) = **15 specs**, validated locally in a throwaway
locust venv (`locust -f … --list` also confirmed the file loads). New cheap
**`loadtest_unit`** job added to `ci.yml` (runs on every push/PR; no backend
clone, no docker stack) and wired into the summary gate.

## Verification done locally

- 15 harness unit specs pass; `locust --list` loads the scenario (sibling
  `from thresholds import` resolves at runtime).
- `heavy-load.yml`, `ci.yml`, `docker-compose.yaml` all parse as valid YAML;
  `docker compose config` validates the new env interpolation.

## What needs a dispatch to confirm (NOT done — flagged for the user)

The §5 acceptance ("re-dispatch returns exit 0, or fails only on a *real*
`error_pct`/`p95`/`p99`/`throughput` signal") can only be proven by running the
**Heavy Load** workflow on GitHub Actions — which requires these changes
committed + pushed to `vbwd-platform` `main` first (the workflow checks out the
pushed repo, not the local tree), and is a billed 50-VU run. Residual risks to
watch on that dispatch:

1. **`flask seed all --strict` vs meinchat idempotency.** S30 saw meinchat's
   `populate()` raise `'alice' already taken` on a *re-seed*; CI's DB is fresh so
   the first seed should be clean. If it trips, switch the workflow to
   `flask seed all --best-effort`.
2. **`populate_db.py --force`.** The old loop passed `--force`; S30's `runpy`
   fallback runs the script argless. On a fresh CI DB this shouldn't matter
   (force is for re-runs), but it's unverified until a dispatch.

## Engineering requirements

TDD-first (15 specs; threshold logic is a pure, independently-tested function),
narrowest change grounded in verified backend contracts, DRY (one
`SCENARIO_ENDPOINTS` list feeds the smoke; one `evaluate()` feeds the run + tests).
Co-operative with S30 (consumes `/_routes`, `/_seed_status`, `flask seed all`).
**Not committed / not dispatched.**
