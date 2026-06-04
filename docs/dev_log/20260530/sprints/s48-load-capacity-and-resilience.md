# S48 — Load capacity & resilience (parent)

**Status:** DRAFT for negotiation — 2026-06-03
**Area:** `vbwd-backend` (config + caching + queries) · `vbwd-platform` (load harness) · infra (pgbouncer + load env).
**Motivated by:** heavy-load runs at 50 / 100 / 500 VU after the S29 harness was hardened — [report 13](../reports/13-heavy-load-validated-engine-speed.md) + the 100-VU run `26869231438` + the 500-VU run `26868887874`.

## Engineering requirements (BINDING)

**TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · NO OVERENGINEERING** (narrowest change that satisfies the requirement) — [`_engineering_requirements.md`](_engineering_requirements.md). **`bin/pre-commit-check.sh` is the quality guard** (`--full`/`--plugin … --full` green = done). **Measure-driven: fix one *proven* bottleneck, re-measure, repeat — never shotgun.** Every capacity change must be validated by a heavy-load re-dispatch, not asserted.

## The evidence (three runs, one hardened harness)

| load | throughput | p50 | p95 | p99 | error% | what broke |
|---|---:|---:|---:|---:|---:|---|
| 50 VU | 37 req/s | 9 ms | 88 ms | 330 ms | 6.1% | only `/tarif-plans/<slug>` (100%) |
| **100 VU** | **73 req/s** | **9 ms** | **110 ms** | **380 ms** | 6.1% | only `/tarif-plans/<slug>` (100%) |
| 500 VU | 139 req/s | 660 ms | 9 200 ms | 19 000 ms | 51% | auth 19 s · 500s everywhere · pool exhaustion |

**Reading:** the engine scales **near-linearly to 100 VU** on a 2-vCPU CI box (throughput ~doubles 50→100, p95 barely moves) — the knee is **between 100 and 500 VU**. At 500 VU three coupled failures appear, all traceable to config:

1. **DB connection pool overcommits Postgres.** `gunicorn workers=4` × SQLAlchemy `pool_size=20 + max_overflow=40 = 60` = **240 possible connections** vs Postgres `max_connections=200` → `FATAL: too many clients` → the 500s. *(A real latent prod bug, independent of the load test.)*
2. **CPU oversubscription / bcrypt herd.** `4 workers × 64 threads = 256` threads on ~2 cores; bcrypt is CPU-bound under the GIL → 500 simultaneous registrations queue to 19 s. *(Amplified by the test registering one fresh user per VU.)*
3. **No graceful degradation.** Under overload the app queues to 19 s and drops connections (`RemoteDisconnected`) instead of fast-failing (503).

Plus a **load-independent functional bug:** `GET /api/v1/tarif-plans/<slug>` returns **400 BAD REQUEST 100%** of the time — it alone is ~83% of the error rate at every load level.

## Honest framing

No config change makes **500 VU pass on a 2-vCPU CI runner** — bcrypt auth + Postgres on 2 cores has an honest ceiling (~150–250 req/s). The capacity sub-sprints make the box **degrade gracefully and reach its true ceiling**; proving 500+ VU needs **prod-sized infra + pgbouncer** (S48.4). Tuning is real and worth doing; it is not a substitute for hardware.

## Sub-sprints (in recommended order)

| # | Sprint | Track | Why this order |
|---|---|---|---|
| **48.5** | [`/tarif-plans/<slug>` 400 fix](s48-5-tarif-plan-slug-400-fix.md) | correctness | Smallest, independent, removes ~83% of measured "errors" — do anytime / first. |
| **48.0** | [Fair load harness](s48-0-fair-load-harness.md) | test realism | Until VUs stop herding bcrypt, we can't separate app bottleneck from test self-harm. |
| **48.1** | [Connection-pool / worker tuning + graceful degradation](s48-1-connection-pool-worker-tuning.md) | server config | Fixes the 240>200 overcommit (a real bug) + fast-fail. Highest leverage, config-only. |
| **48.2** | [Catalog read cache (Redis)](s48-2-catalog-read-cache.md) | caching | Offloads the heaviest, read-mostly traffic from Postgres. |
| **48.3** | [Admin query efficiency](s48-3-admin-query-efficiency.md) | queries | Tightens the tail (admin joins degrade worst under load). |
| **48.4** | [pgbouncer + prod-sized load env](s48-4-pgbouncer-and-load-env.md) | infra | Lifts the real ceiling + lets us test 500+ VU meaningfully. |

Each sub-sprint is independently shippable and gated on a heavy-load re-dispatch. **Do not** treat the whole set as one big-bang change.

## Out of scope (parent)

- Rewriting auth to be non-bcrypt or async (bcrypt cost is the correct default 12 — keep it).
- Horizontal app autoscaling / k8s (a deployment-topology workstream, not a code one).
- Migrating off Locust / the CI-runner load target (S48.4 addresses the env minimally).
