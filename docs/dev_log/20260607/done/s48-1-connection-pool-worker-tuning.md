# S48.1 — Connection-pool / worker tuning + graceful degradation

**Status:** PLANNED — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-backend` — `gunicorn.conf.py`, `vbwd/config.py` (`SQLALCHEMY_ENGINE_OPTIONS`), `docker-compose.yaml` (Postgres). **Config-only; no business-logic change.**

## Engineering requirements (BINDING)

DevOps-first · SOLID · DRY · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --full` stays green (the connection-exhaustion teardown infra from 2026-05-25 must remain green); validated by a heavy-load re-dispatch. **No DB writes outside Alembic** ([[feedback_migrations_only]]) — this sprint touches no schema.

## Problem (a real latent prod bug, from config math)

- `gunicorn.conf.py`: `workers=4`, `worker_class=gthread`, `threads=64`, `timeout=120`.
- `vbwd/config.py`: `pool_size=20`, `max_overflow=40` → **60 connections per worker**.
- `docker-compose.yaml`: Postgres `max_connections=200`.

`4 workers × 60 = 240 > 200` → under load workers exceed Postgres's limit → `FATAL: sorry, too many clients already` → the **500s seen across all endpoints at 500 VU**. Separately, `64 threads × 4 = 256` request threads on ~2 cores oversubscribe CPU, and `64 threads/worker > 60 connections/worker` means threads block on the pool. And `timeout=120` means an overloaded worker hangs up to 2 minutes (→ the 19 s+ waits and `RemoteDisconnected`) instead of shedding load.

This overcommit is **independent of the load test** — it can bite real production the moment concurrency rises.

## Goal

Make the connection math safe by construction, align threads to the pool, right-size workers to cores, and **fail fast under overload** (quick 503) instead of queueing to timeout. The box should *degrade gracefully* and reach its honest ceiling.

## Design

Invariant to enforce (and document next to the settings): **`workers × (pool_size + max_overflow) + reserve ≤ Postgres max_connections`**.

- **Pool (`vbwd/config.py`):** make `pool_size` / `max_overflow` env-driven (`DB_POOL_SIZE`, `DB_MAX_OVERFLOW`) with safe defaults, e.g. `pool_size=10, max_overflow=10` → 20/worker. With `workers=4` → 80 ≤ 200 (ample reserve for migrations/superuser/admin). Keep `pool_pre_ping=True`; add `pool_recycle` to drop stale conns.
- **Gunicorn (`gunicorn.conf.py`):** make `workers` env-driven and **default to cores** (`(2 × CPU) + 1`) rather than a hardcoded 4; set `threads` ≈ `pool_size` (no point having more threads than connections). Lower `timeout` to a load-shedding value (e.g. 30 s) so a stuck worker recycles. Keep `max_requests` jitter (already present) to recycle workers.
- **Postgres (`docker-compose.yaml`):** keep `max_connections=200`; document that real horizontal scale uses **pgbouncer** (S48.4), not a bigger number.
- **Graceful degradation:** add a SQLAlchemy `pool_timeout` (e.g. 5 s) so a request waits briefly for a connection then returns **503** (fast-fail) instead of hanging; optionally set Postgres `statement_timeout` so a slow query can't pin a connection indefinitely. Map pool-timeout / OperationalError to a clean `503 Service Unavailable` with `Retry-After`, not a 500.

All values env-driven so prod (many cores, pgbouncer) and CI (2 cores) use the same code with different env.

## TDD plan

- **Unit:** a config invariant test — `workers × (pool_size + max_overflow) ≤ max_connections − reserve` for the documented default env (a guard that fails CI if someone reintroduces the 240>200 overcommit).
- **Unit:** the engine-options builder reads `DB_POOL_SIZE`/`DB_MAX_OVERFLOW`/`pool_timeout` from env and falls back to safe defaults.
- **Unit/integration:** when the pool is exhausted (simulate `pool_timeout`), the error handler returns **503 + Retry-After**, not 500.
- The existing `bin/pre-commit-check.sh --full` connection-exhaustion teardown must stay green.

## Acceptance

- The invariant test passes; the overcommit cannot regress silently.
- Heavy-load re-dispatch at 500 VU: the `FATAL: too many clients` 500s disappear; overload surfaces as **503 fast-fails** (bounded latency), not 19 s hangs + dropped connections. p99 under overload bounded by `timeout`, not 120 s.
- 100 VU stays green on latency (p95 ≤ budget) after tuning.

## Out of scope

- pgbouncer + raising real connection ceilings → **S48.4**.
- Caching to reduce DB load → **S48.2**.
