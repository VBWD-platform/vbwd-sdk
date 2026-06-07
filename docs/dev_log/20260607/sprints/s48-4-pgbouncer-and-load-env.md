# S48.4 — pgbouncer + a prod-sized load-test environment

**Status:** DRAFT for negotiation — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** infra — `docker-compose.yaml` (+ the prod compose / deploy topology) + the heavy-load workflow target. **Deployment/ops, not application logic.**

## Engineering requirements (BINDING)

DevOps-first · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). **Never edit the prod demo-instance compose files as if local** ([[feedback_never_mix_local_and_prod_compose]]); deploys are GitHub-Actions-only ([[feedback_deploy_github_only]]). Validated by heavy-load re-dispatches at 100 / 250 / 500 VU.

## Problem

Two limits remain after S48.1–S48.3, both about *where* and *how* we run, not the code:

1. **Connection ceiling.** Even with safe per-worker pools, scaling **app workers** (prod has many cores) eventually exceeds Postgres `max_connections`. The standard fix is a **connection pooler** (pgbouncer, transaction mode) so N app workers multiplex onto a small set of real PG connections.
2. **The load target is a 2-vCPU CI runner.** It cannot honestly serve 500 VU regardless of tuning (bcrypt + PG on 2 cores). Conclusions about "vbwd at 500 VU" drawn from the CI box are about the *box*, not the app.

## Goal

(a) Put pgbouncer in front of Postgres so app concurrency scales independently of `max_connections`; (b) give the heavy-load workflow a **prod-sized target option** so 250–500 VU runs measure the application, not the runner.

## Design

### pgbouncer
- Add a `pgbouncer` service (transaction pooling) between the app and Postgres; point `DATABASE_URL` at pgbouncer. Set `default_pool_size` / `max_client_conn` so many app workers share a small PG connection set (e.g. 25 real PG conns serving hundreds of app clients).
- **Transaction-mode caveats:** no session-level features (no `SET`, server-side prepared statements off / use `prepare_threshold=0`). Verify SQLAlchemy + the app's session usage are transaction-pooling-safe; document any setting (e.g. disable prepared statements) — this is the main review risk.
- Keep S48.1's per-worker pool small; pgbouncer becomes the real multiplexer.

### Prod-sized load target
- Heavy-load workflow already has a `target_url` input. Add a documented path to point it at a **dedicated load environment** (a right-sized VM / managed Postgres), separate from the ephemeral CI stack. Keep the CI-stack run as a cheap smoke; use the sized env for capacity numbers.
- Document the two modes in `tests/load/README.md`: *CI smoke* (functional + low-VU regression) vs *capacity run* (sized env, 250–500 VU).

## Validation plan

- pgbouncer up locally: full `bin/pre-commit-check.sh --full` green through pgbouncer (catch transaction-pooling incompatibilities); a 100-VU heavy-load run green through pgbouncer with no `too many clients`.
- A 250 / 500-VU run against the sized env shows the **real** knee (throughput continues scaling past the CI box's ~140 req/s ceiling).

## Acceptance

- App talks to Postgres via pgbouncer with the test suite green (no session-pooling breakage).
- Capacity runs at 250–500 VU produce trustworthy numbers from sized infra; the CI run remains a fast functional smoke.
- A short capacity note records the measured prod-sized ceiling + the next bottleneck.

## Out of scope

- Read replicas / sharding / multi-AZ HA (separate scaling epic).
- Autoscaling policy / k8s topology.
- Changing the deploy pipeline beyond adding the pooler service + a documented load target.
