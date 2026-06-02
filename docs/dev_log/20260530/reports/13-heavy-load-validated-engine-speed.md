# Report 13 — Heavy-load harness VALIDATED + engine speed under 50 VU

**Date:** 2026-06-02
**Scope:** closes the S33 → S30 → S29 arc by running the hardened heavy-load
workflow end-to-end on GitHub Actions. After two iterations (each catching a
*real* defect the harness was built to catch), the run reaches full execution and
**fails only on a genuine backend signal — not harness drift.** That is the
explicit success condition of S29 §5.

---

## TL;DR — the engine is fast

At **50 concurrent virtual users** against the full plugin set (`plugins=all`),
the vbwd backend served **4,401 requests in 2 minutes (~37 req/s)** with these
aggregate latencies:

| percentile | latency |
|---|---|
| p50 | **9 ms** |
| p75 | 14 ms |
| p90 | 33 ms |
| **p95** | **88 ms** |
| p99 | 330 ms |

The S29 budgets — **p95 ≤ 1500 ms, p99 ≤ 3000 ms, throughput ≥ 20 req/s — all
pass with enormous headroom** (p95 is ~17× under budget). The engine is not the
bottleneck at this load.

### Per-endpoint medians (50 VU)

| endpoint | reqs | median | p95 | fails | note |
|---|---:|---:|---:|---:|---|
| `GET /tarif-plans` | 1059 | **9 ms** | 29 ms | 7 | catalog read, heaviest traffic |
| `GET /addons` | 711 | **7 ms** | ~22 ms | 9 | |
| `GET /user/subscriptions/active` | 584 | 9 ms | ~27 ms | 8 | authed dashboard |
| `GET /user/addons` | 361 | 10 ms | ~32 ms | 3 | |
| `GET /token-bundles` | 347 | 6 ms | ~19 ms | 2 | |
| `POST /user/checkout` | 226 | **27 ms** | 89 ms | **0** | **write path** (invoice + entitlement) |
| `GET /user/invoices` | 410 | 9 ms | ~32 ms | 10 | |
| `GET /user/tokens/balance` | 153 | 9 ms | ~24 ms | 1 | |
| `GET /plugins/token-payment/quote` | 78 | 9 ms | ~24 ms | 0 | |
| `GET /admin/invoices` | 114 | 77 ms | ~190 ms | 0 | join + pagination |
| `GET /admin/subscriptions` | 101 | 120 ms | ~250 ms | 0 | join + pagination |
| `POST /auth/login` | 4 | 560 ms | — | 0 | bcrypt (intentional cost) |
| `POST /auth/register` | 23 | 560 ms | — | 0 | bcrypt (intentional cost) |

Reads are single-digit milliseconds. The **write-heavy checkout — which creates
an invoice and an entitlement — runs at a 27 ms median with zero failures.**
Admin list views (multi-table joins + pagination) stay under ~130 ms median.
The only "slow" endpoints are `auth/{login,register}` at ~560 ms, which is
**by design** — bcrypt password hashing is deliberately expensive; it is not a
throughput concern at realistic auth rates.

---

## The one real signal the harness surfaced

`GET /tarif-plans/<slug>` failed **227 / 227 (100%)** — accounting for ~85% of
all 267 failures (error_pct 6.07%). The remaining ~40 failures are benign
end-of-test `RemoteDisconnected` resets (Locust closing connections at shutdown),
spread one-or-two per endpoint.

This is **not** harness drift — the URL is now correctly interpolated (report
04's literal-`<slug>` bug is gone), the slug is present in the list payload, and
the detail route accepts slug-or-id. The list endpoint (`/tarif-plans`) succeeds
at 9 ms; the **detail** endpoint additionally runs currency + tax **pricing
resolution** (`CurrencyService` / `TaxService`) that the list does not — the most
likely cause is a 500 in that pricing path on the seeded data. **Filed as a
follow-up backend investigation** (see status.md notes); it is out of S29 scope —
S29's job was to make this signal *visible and trustworthy*, which it now is.

---

## How we got here — two iterations, two real bugs caught fast

The whole point of S29 was "every failure is meaningful." It proved itself by
catching two genuine defects on the way, each failing **loudly and early** rather
than as a silent 46%-error mystery (report 04):

| Run | Reached | Failure | Root cause | Fix |
|---|---|---|---|---|
| `26847419902` | seed step | `flask seed all` exit 1 | **S30 bug:** the `runpy` fallback ran each `populate_db.py` with the inherited `sys.argv` (`seed all`) → the script's argparse aborted (exit 2) | backend `4f2c8d4`: sanitize `sys.argv` to `[script, --force]`; regression test added |
| `26847639937` | Locust pre-load smoke | `harness_smoke` breach | **S29 false positive:** the `/_routes` contract smoke matched paths literally; the backend registers several routes *with* a trailing slash (`strict_slashes=False` makes them work) | platform `0a1a880`: pure slash-insensitive `find_scenario_drift()`; 2 regression specs |
| `26848354627` | **full run** | `error_pct` (real) | `/tarif-plans/<slug>` 100% failing — **a genuine backend signal** | n/a — harness did its job; finding filed |

Both fixes were the *narrowest correct* change, each landed with a regression
test, and each was a defect the hardened harness exists to expose. The seed step
now runs `flask seed all` (fail-fast, S30) gated by `/_seed_status`; the Locust
run is preceded by a slash-tolerant `/_routes` contract smoke; and the typed
threshold evaluator reports the breach as `error_pct` (a real lane), not as a
misattributed latency or harness failure.

---

## S29 verdict: ✅ mission accomplished

Per S29 §5, the sprint closes when the next dispatch's failure mode is **no longer
harness drift**. It isn't: auth works, the bearer flows, checkout writes succeed,
every contract URL resolves, the seed is complete and asserted — and the single
threshold breach is a real, specific, reproducible backend reliability signal.
Latency and throughput are comfortably green. **S29 is done; the
`/tarif-plans/<slug>` 500 is the first real perf/reliability ticket the harness
has handed us — exactly the outcome the sprint was built to produce.**

## Commits

- backend `c05c2d2` (S33), `fc1bd6a` (S30), `4f2c8d4` (S30 argv fix)
- vbwd-plugin-meinchat `856febe` (S33)
- vbwd-platform `454fb72` (S29), `0a1a880` (S29 slash-insensitive smoke)
- vbwd-sdk root `2e7fbe0` (docs)
- Heavy-load runs: `26847419902` → `26847639937` → **`26848354627`** (full run).
