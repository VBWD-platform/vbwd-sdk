# S38 — meinchat SSE event bus: one Redis connection per worker + fail-loud backend

**Status:** IMPLEMENTED & GREEN — 2026-05-29 (decisions in §7 resolved). 36
event-bus specs pass (contract suite ×2 backends + cross-worker + connection-
count + selection); full meinchat suite 206 passed / 5 skipped; black + flake8
(`--max-line-length=120`) + mypy clean. No commit (per
[[feedback_no_commit_without_ask]]).
**Repo:** `vbwd-backend` / `plugins/meinchat` (plugin-internal; **no core change**).
**Trigger:** the 2026-05-28 prod freeze — meinchat SSE streams on `sync`
gunicorn workers starved every other request. Hotfix shipped: gunicorn
→ `gthread` + `threads=64`, SSE lifetime cap + DB-connection release
(`gunicorn.conf.py`, `plugins/meinchat/meinchat/routes.py`,
`…/services/event_bus.py`). That hotfix raised the concurrent-stream ceiling
from ~4 to ~256 — which **amplifies** a latent design flaw in the existing
`RedisEventBus`: it opens **one Redis connection per open stream**. This sprint
removes that, and closes a silent-degradation hole in backend selection.
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · NO OVERENGINEERING —
[`_engineering_requirements.md`](_engineering_requirements.md).
Gate: `bin/pre-commit-check.sh --full` green.

---

## 1. Goal

meinchat real-time fan-out across gunicorn workers is correct **and** scales:
a worker holds **one** Redis pub/sub connection regardless of how many SSE
streams it serves, the active backend is chosen **once** and **logged** (prod
never silently degrades to the single-worker in-process bus), and both bus
backends provably honour one shared contract.

## 2. Current state (grounded) — what already works, what doesn't

A Redis-backed bus **already exists and is already the default** — so prod is
*already* doing cross-worker delivery (this corrects an earlier assumption that
fan-out was in-process-only in prod). The factory `routes.py:186-204` prefers
Redis and falls back to in-process only when Redis is unreachable. Publishers
are unchanged callers of one interface
(`message_service.py:82` → `self._event_bus.publish(f"user:{id}", body)`).

Two real defects remain:

### 2a. One Redis connection **per stream** (scaling flaw, now amplified)
`redis_event_bus.py:81-88` — every `subscribe()` does `self._redis.pubsub()` +
`pubsub.subscribe(channel)`, i.e. a **dedicated connection per subscriber**, and
`_RedisSubscription.iter_events` (`:30-63`) blocks on
`pubsub.get_message(timeout=…)` holding that connection for the whole stream
(`close()` at `:65-72` tears it down). With the new gthread ceiling (4×64≈256
streams) that is up to ~256 Redis connections **just for SSE**, plus
rate-limiter / cache / celery connections. This is the connection-per-stream
anti-pattern: it pressures the redis-py pool and Redis `maxclients`, and any
missed `close()` (client vanished, generator not finalized) **leaks** a Redis
connection — a slow-bleed that itself degrades the platform over time.

### 2b. Silent, **sticky** fallback to the broken backend (reliability hole)
`routes.py:196-203` wraps backend selection in `except Exception: bus =
MeinchatEventBus()` and caches the result on `current_app` **for the worker's
lifetime**. A *transient* Redis blip at the moment a worker first serves a
stream pins that worker to the **in-process** bus permanently — so its SSE
clients silently stop receiving events published by other workers, with **no
log, no alarm**. Selection must happen once at startup, be explicit, and be
loud.

### 2c. No reconnect / no tests
No backoff if the listener's Redis connection drops mid-life; no test coverage
for `RedisEventBus` at all (only the in-process `event_bus` is tested).

## 3. Design

### 3a. One listener thread per worker → fan into the shared queue subscription
Refactor `RedisEventBus` to the **single-subscriber-per-process** pattern,
reusing the already-tested queue-based subscription from the in-process bus
(DRY — the only difference between backends becomes *who feeds the queue*):

1. **Extract** the queue-based `_Subscription` (today in `event_bus.py:15-72`
   — `queue.Queue`, `deliver`, `iter_events` with heartbeat + the hotfix's
   lifetime cap, `close`) into a shared module both backends import. The SSE
   route keeps calling `iter_events(timeout=max_stream_s)` unchanged.
2. `RedisEventBus` keeps a local registry `channel → [_Subscription]` (the same
   lock-guarded structure as `MeinchatEventBus`) and **one** background daemon
   listener thread holding **one** Redis pub/sub connection that
   `psubscribe(f"{prefix}*")` (prefix `meinchat:`). On each message the listener
   decodes JSON and `deliver()`s into the local subscriptions for that channel.
3. `subscribe()` now just creates a local `_Subscription`, registers it, and
   returns it — **no per-stream Redis connection**. `publish()` is unchanged
   (`redis.publish`, pooled, thread-safe). `close()` only unregisters locally.
4. **Channel namespacing:** the bus internally prefixes logical channels
   (`user:{id}` → `meinchat:user:{id}`) so the pattern subscribe can't catch
   foreign channels. Callers (`message_service`) are unchanged (OCP).
5. **Reconnect:** the listener reconnects with bounded backoff on Redis drop and
   never crashes the worker; local streams keep heartbeating until it returns.

> **NO OVERENGINEERING:** v1 uses one `psubscribe` pattern per worker (simplest
> thing that gives one connection). Dynamic per-channel subscribe (less fan-out
> traffic at large scale) is noted as the scale path, not built now. Heartbeats
> stay **local** (never round-trip Redis). Delivery stays **at-most-once** —
> messages are already persisted in the DB; SSE is a live nudge, and the FE
> refetches the conversation on reconnect (`useMessagingStream.ts`), so a
> dropped event self-heals. No replay/queue durability is added.

### 3b. Decide the backend once, explicitly, loudly
- New meinchat config key `event_bus_backend` ∈ `{auto, redis, memory}`
  (default `auto`) + `event_bus_channel_prefix` (default `meinchat:`).
- Resolve the bus **once** (plugin `on_enable` / container singleton), not per
  request. Log the chosen backend at INFO.
- `redis`: Redis unreachable at startup → **fail loud** (raise) — never degrade.
- `auto`: prefer Redis; if unreachable, use in-process **with a WARNING** that
  names the consequence ("SSE limited to a single worker").
- Remove the per-request `try/except Exception` + `current_app` caching that
  causes the sticky silent fallback.
- Surface the active backend on the meinchat health/status endpoint so ops can
  confirm `redis` is live.

### SOLID / DRY / Liskov
- **ISP/DIP:** both backends satisfy one narrow `EventBus` interface
  (`subscribe`, `publish`, `channel_count`); consumers depend on the interface.
- **DRY:** the queue-based `_Subscription` is shared; only the feeder differs.
- **Liskov:** a single parametrized contract suite runs against **both**
  backends — identical observable behaviour; the SSE route works with either.
- **OCP:** publishers/SSE route unchanged; backend swap + prefixing are internal.

## 4. TDD (RED first)

1. **Shared contract suite** parametrized over `[InProcessEventBus,
   RedisEventBus]` — subscribe receives published event; channel scoping
   isolates users; multiple subscribers on a channel all receive; unsubscribe
   stops delivery; heartbeat fires at the configured interval; `iter_events`
   honours the lifetime cap (the hotfix regression). The Redis case is
   integration — skip-with-log when Redis is absent
   ([[feedback_ci_precommit_lessons]] — no silent skips).
2. **Headline cross-worker test:** two separate `RedisEventBus` instances
   (simulating two workers) sharing one Redis — `publish` on instance A reaches
   a subscriber registered on instance B. Proves §2-fan-out and guards it.
3. **Connection-count test:** open + close 50 subscriptions →
   `redis.info("clients")` returns to baseline (no leak) and shows ~**1** extra
   connection (the listener) while many streams are open, **not** 50.
4. **Backend-selection tests:** `event_bus_backend=redis` + Redis down → raises
   at enable (no memory fallback); `auto` + Redis up → `RedisEventBus`; `auto` +
   Redis down → in-process **and** a WARNING logged.
5. Existing `test_event_bus.py` (8, incl. the hotfix's lifetime-cap guards) stays
   green against the in-process backend.

## 5. Files

| Action | Path |
| --- | --- |
| new  | `plugins/meinchat/meinchat/services/event_bus_base.py` — shared `EventBus` interface + queue-based `_Subscription` |
| edit | `plugins/meinchat/meinchat/services/event_bus.py` — `MeinchatEventBus` reuses shared `_Subscription` |
| edit | `plugins/meinchat/meinchat/services/redis_event_bus.py` — one listener thread + local fan-out + prefix + reconnect |
| edit | `plugins/meinchat/meinchat/routes.py` — resolve backend once (no sticky silent fallback); expose backend on health |
| edit | `plugins/meinchat/__init__.py` — choose/validate backend in `on_enable`; log it |
| edit | `plugins/meinchat/config.json` + `admin-config.json` — `event_bus_backend`, `event_bus_channel_prefix` |
| new  | `plugins/meinchat/tests/unit/services/test_event_bus_contract.py` — parametrized contract suite |
| new  | `plugins/meinchat/tests/integration/test_redis_event_bus.py` — cross-worker + connection-count |
| new  | `plugins/meinchat/tests/unit/test_event_bus_selection.py` — backend selection |

## 6. Acceptance (done = all of)

- A worker holds **one** Redis connection for SSE fan-out regardless of open
  stream count (connection-count test green); no connection leak on
  subscribe/close churn.
- Cross-worker delivery proven by the two-instance integration test.
- Backend is chosen once, logged, and **never** silently degrades in prod
  (`redis` mode fails loud; `auto` warns); active backend visible on health.
- Both backends pass the one shared contract suite (Liskov); all existing
  meinchat tests stay green.
- All changes inside `plugins/meinchat` — core untouched; agnosticism oracles
  green.
- `bin/pre-commit-check.sh --full` green. No `# noqa`/`# type: ignore` without
  approval ([[feedback_no_noqa_without_permission]]); no commits unless
  instructed ([[feedback_no_commit_without_ask]]).

## 7. Decisions (resolved 2026-05-29)

1. **Fan-out strategy → `psubscribe` pattern per worker.** One listener
   connection psubscribes `<prefix>*` and fans into local subscriptions.
   Race-free, trivial reconnect, negligible amplification at human-chat scale;
   dynamic per-channel subscribe is the documented scale path (internal swap,
   zero caller impact — OCP).
2. **Backend default → config `auto`; prod pins `redis`.** `auto` keeps
   dev/CI/no-Redis booting; prod env sets `event_bus_backend=redis` to fail
   loud. The active backend is logged at startup (`create_event_bus`); `redis`
   raises `EventBusUnavailableError` when Redis is down, `auto` warns and
   degrades — never the old silent+sticky fallback.
3. **Redis multi-worker is the standard topology.** Single-worker
   (`GUNICORN_WORKERS=1` + high `GUNICORN_THREADS`) is kept as a documented
   escape hatch only (`event_bus_backend=memory`/`auto`), flagged "limited
   throughput, no redundancy" — because Redis is already mandatory for the stack
   (limiter + celery + cache), single-worker buys no real dependency saving.

## 8. Implementation notes (what shipped)

- New `services/event_bus_base.py` — shared `EventBus` port + queue-based
  `Subscription` (heartbeat + lifetime cap); both backends reuse it (DRY).
- `services/event_bus.py` (`MeinchatEventBus`) reuses the shared `Subscription`.
- `services/redis_event_bus.py` rewritten: one daemon listener thread +
  `psubscribe` + local fan-out + prefix namespacing + bounded-backoff reconnect
  + `wait_listening`/`stop` lifecycle. **No per-stream Redis connection.**
- New `services/event_bus_factory.py` — `create_event_bus(backend, prefix,
  redis_client)`; `routes.py:_event_bus()` resolves once via it (no silent
  fallback). `__init__.py on_disable` stops the listener (no thread leak).
- Config: `event_bus_backend`, `event_bus_channel_prefix`, `sse_max_stream_seconds`
  added to `DEFAULT_CONFIG` + `config.json` (admin-visible).
- **Descoped (NO OVERENGINEERING):** no new admin health endpoint — the active
  backend is surfaced via the startup INFO/WARNING log instead of a new
  route+permission. Backend is resolved lazily-once-per-worker (cached on
  `current_app`) rather than at `on_enable`, to avoid coupling app boot to Redis
  liveness; still "once + loud" (logs on first use; `redis` mode raises loudly
  on every request until Redis returns, never caching a degraded bus).
- Tests: `tests/unit/services/test_event_bus_contract.py` (parametrized ×2
  backends), `tests/integration/test_redis_event_bus.py` (cross-worker delivery
  + one-listener connection-count + clean stop), `tests/unit/test_event_bus_selection.py`.
