# Report 06 — meinchat SSE worker-starvation prod freeze: hotfix + S38 Redis-bus hardening

**Date:** 2026-05-29
**Author:** Claude (Opus 4.8)
**Repos touched:** `vbwd-backend` (`gunicorn.conf.py`, `plugins/meinchat/**`)
**Sprints:** S-incident hotfix (unnumbered) + [S38](../done/s38-meinchat-redis-bus-hardening.md)
**Status:** IMPLEMENTED & GREEN — **not committed, not deployed** (awaiting user
redeploy through the normal path).

---

## 1. Incident

Production (`vbwd.cc`) became very slow: the admin app's `GET /profile` XHR hung
~30 s and was canceled by the browser; `GET /admin/settings` took 12.5 s. The
network tab showed every static asset served from disk cache in ~0 ms — only the
**backend API calls** were slow. The user's key observation: "there is a second
user on the server and his requests block mine — this is supposed to be a
multiuser platform." A third screenshot showed a `meinchat` XHR canceled at
**exactly 30.00 s** alongside `profile` at 30.02 s.

## 2. Root cause

meinchat uses **Server-Sent Events** — `GET /api/v1/messaging/stream`
(`plugins/meinchat/meinchat/routes.py`) returns a long-lived `text/event-stream`
that stays open for the whole browser session, blocking inside
`event_bus.py`'s `iter_events` on a `queue.get(timeout=…)` loop.

gunicorn ran `worker_class = "sync"` with `workers = 4`. A **sync** worker serves
exactly one request at a time and cannot be preempted, so **each open chat tab
permanently parked one of the four workers**. ~4 chat tabs anywhere on the
platform → all workers consumed by idle SSE streams → every other request
(`/profile`, `/admin/settings`) had no free worker, queued, and was canceled at
the browser's 30 s timeout. This is head-of-line blocking, not a capacity
shortfall — raising the worker count only changes how many tabs it takes to
freeze.

A latent secondary issue: under `@stream_with_context` the request (and its DB
session) lives for the whole stream, so an idle stream could also pin a DB-pool
connection. And `iter_events()` was called with **no timeout** → the loop ran
forever.

## 3. Hotfix (applied, verified green)

Minimal, behaviour-preserving for the non-streaming path:

- **`gunicorn.conf.py`** — `worker_class = os.getenv("GUNICORN_WORKER_CLASS",
  "gthread")` + `threads = GUNICORN_THREADS (64)`. A `gthread` worker serves many
  connections via threads; a thread blocked on the SSE queue releases the GIL, so
  streams no longer block normal traffic (~4 → ~256 concurrent connections).
  **gthread, not gevent** — the event bus uses a blocking `queue.Queue` that
  cooperates with OS threads but not with un-monkey-patched greenlets.
- **SSE handler** (`routes.py`) — `db.session.remove()` before the wait loop
  (release the pool connection during the idle wait) + `iter_events(timeout=
  cfg.sse_max_stream_seconds, default 600)` to cap each stream's life. The
  browser's `EventSource` auto-reconnects, so the cap is invisible.
- Regression tests in `tests/unit/services/test_event_bus.py`
  (`TestStreamLifetimeCap`).

The flake8 gate uses `--max-line-length=120` (`bin/pre-commit-check.sh:174`), not
the 79 default — worth remembering when ad-hoc linting.

## 4. S38 — Redis event-bus hardening (follow-up, the freeze's deeper fix)

The hotfix raised the concurrent-stream ceiling, which **amplified** a latent
flaw and exposed a reliability hole in the already-present Redis bus.

### 4.1 What was wrong
- `RedisEventBus` opened **one Redis pub/sub connection per open stream**
  (`self._redis.pubsub()` in every `subscribe()`). ~256 streams → ~256 Redis
  connections, plus a leak on any missed `close()`.
- `_event_bus()` wrapped backend selection in `except Exception:` and cached the
  result on `current_app` for the worker's life — a **transient** Redis blip
  pinned a worker to the broken **in-process** bus permanently, with no log. In a
  multi-worker deployment that means some users silently stop receiving
  cross-worker messages (looks like a flaky bug).

### 4.2 What shipped
- **`services/event_bus_base.py`** (new) — shared `EventBus` port + queue-based
  `Subscription` (heartbeat + lifetime cap). Both backends reuse it (DRY); the
  only difference is who feeds the queue (Liskov).
- **`services/event_bus.py`** — `MeinchatEventBus` reuses the shared
  `Subscription`.
- **`services/redis_event_bus.py`** — rewritten to **one daemon listener thread
  per worker** holding **one** Redis connection that `psubscribe`s `<prefix>*`
  and fans incoming messages into local subscriptions. Prefix namespacing,
  bounded-backoff reconnect, `wait_listening` / `stop` lifecycle. Connection
  count is now independent of stream count.
- **`services/event_bus_factory.py`** (new) — `create_event_bus(backend, prefix,
  redis_client)`: `memory` → in-process; `redis` → require Redis or raise
  `EventBusUnavailableError` (fail loud); `auto` → prefer Redis, else in-process
  with a WARNING. Choice logged. `routes.py:_event_bus()` resolves once via it —
  no silent fallback. `__init__.py:on_disable` stops the listener (no leak).
- **Config** — `event_bus_backend`, `event_bus_channel_prefix`,
  `sse_max_stream_seconds` added to `DEFAULT_CONFIG` + `config.json`.

### 4.3 Decisions (resolved with the user)
1. **`psubscribe` pattern** per worker — simplest, race-free, trivial reconnect;
   amplification is negligible at human-chat scale. Dynamic per-channel subscribe
   is the documented scale path (internal swap, zero caller impact).
2. **Config default `auto`; prod pins `event_bus_backend=redis`** — dev/CI boot
   without Redis; prod fails loud. Active backend is logged at startup.
3. **Redis multi-worker is the standard topology.** Single-worker
   (`GUNICORN_WORKERS=1` + high threads, `memory`/`auto` backend) is a documented
   escape hatch only — Redis is already mandatory (limiter + celery + cache), so
   single-worker saves no real dependency.

### 4.4 Deliberate descopes (NO OVERENGINEERING)
- No new admin health endpoint — the active backend is surfaced via the startup
  INFO/WARNING log rather than a new route + permission.
- Bus resolved lazily-once-per-worker (cached on `current_app`) rather than at
  `on_enable`, to avoid coupling app boot to Redis liveness. Still "once + loud":
  logs on first use; `redis` mode raises on every request until Redis returns and
  never caches a degraded bus.

## 5. Verification

- **Event-bus specs: 36 passed** — parametrized contract suite across both
  backends (subscribe/scope/multi-sub/unsubscribe/heartbeat/lifetime-cap), the
  headline **cross-worker delivery** integration test (publish on one simulated
  worker → subscriber on another receives), the **connection-count** regression
  (50 streams add ~1 Redis connection, not 50), clean listener stop, and backend
  selection (memory/redis/auto, fail-loud).
- **Full meinchat suite: 206 passed / 5 skipped** (pre-existing skips).
- **black + flake8 (`--max-line-length=120`) + mypy: clean.**

## 6. Deployment guidance (pending user action)

- The hotfix and S38 are **uncommitted and undeployed**; ship them **together** —
  gthread unblocks the freeze, S38 makes the now-256-stream ceiling safe on Redis.
- Deploy via the normal path; **do not hand-edit the prod compose tree** (CI
  scp's it).
- Set **`event_bus_backend=redis`** in the prod env so it fails loud instead of
  degrading. Tunable knobs: `GUNICORN_WORKERS`, `GUNICORN_THREADS`,
  `GUNICORN_WORKER_CLASS`, `sse_max_stream_seconds`, `event_bus_channel_prefix`.

## 7. Follow-ups (not in scope)

- Dynamic per-channel subscribe if cross-worker fan-out traffic ever shows up in
  metrics (internal `RedisEventBus` change).
- Optional admin JSON probe for the active backend if ops want machine-readable
  health beyond the log line.
- Add `GUNICORN_*` + `event_bus_backend` to `.env.example` / prod env template.
