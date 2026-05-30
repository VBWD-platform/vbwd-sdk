# Report 07 — Daily wrap-up (2026-05-29)

**Date:** 2026-05-29
**Scope:** summary of all Claude sessions today across planning, a prod
incident, and implementation. **Nothing committed or deployed** — all work
sits in the workspace for user review + commit per the standing rule.

---

## 1. Headline

A prod outage was diagnosed and hotfixed, five sprints were planned, and four
slices were implemented test-first to a green gate — including the start of the
meinchat E2E-encryption track (S28 Phase 2).

## 2. Prod incident — meinchat SSE worker starvation (hotfixed)

vbwd.cc froze whenever a second user was active: `/profile` and
`/admin/settings` hung ~30 s. Root cause: meinchat **SSE streams** parked the
**sync** gunicorn workers (4 of them) — a few open chat tabs consumed every
worker. Fixed with `worker_class=gthread` + `threads=64`, an SSE lifetime cap,
and a DB-connection release in the stream handler. Detail + the follow-up:
[`reports/06-sse-worker-starvation-and-redis-bus-hardening.md`](06-sse-worker-starvation-and-redis-bus-hardening.md).

## 3. Implemented & green today

| Slice | What | Gate | Report |
|---|---|---|---|
| **S29** | fe-user `/` no-chrome-flash (scoped flash-only) | fe-user 557 tests + e2e green | [05](05-s28-phase1-and-s29-implementation.md) |
| **S28.0/1/2** | meinchat Phase 1 — config + `/limits`, server retention prune, encrypted client cache (**no crypto/E2E**) | backend + web green | [05](05-s28-phase1-and-s29-implementation.md) |
| **Hotfix** | gunicorn `sync`→`gthread`, SSE lifetime cap + DB release | 8 event-bus specs | [06](06-sse-worker-starvation-and-redis-bus-hardening.md) |
| **S38** | meinchat SSE bus: one Redis connection/worker + fail-loud backend selection | 36 event-bus specs; full meinchat 206 | [06](06-sse-worker-starvation-and-redis-bus-hardening.md) |
| **S28.3a** | meinchat extension ports (registry + 5 ports + defaults), e2e schema columns + constraints, `send_text` port routing, `/messaging/capabilities[?me=true]`, conversation negotiation, migration `20260528_1100` | **241 meinchat specs / 5 skipped; lint clean** | this report |
| **S28.3b (start)** | `meinchat_plus` plugin scaffold + `SignalEnvelopeValidator` (server holds no keys) + config/admin-config + `cbor2` dep | **9 validator specs; lint clean** | this report |

Also: meinchat `admin-config.json` extended to expose **all 27** `config.json`
keys across 5 tabs (added Retention `prune_cron` + a new "Streaming (SSE)" tab).

## 4. Planned today (sprint docs drafted)

- **S36** — discounts & coupons at checkout (diagnosis: backend plugin + admin
  CRUD ship, but the consumer checkout path was never built).
- **S37** — fe-user "Pay Zero" checkout (port the iOS zero-cost flow).
- **S38** — meinchat Redis-bus hardening (implemented same day, above).

## 5. Operational must-knows (carried into tomorrow)

- **Nothing is committed or deployed.** The prod hotfix + S38 should ship
  together via the normal deploy path (not by editing the prod compose tree);
  set `event_bus_backend=redis` in the prod env (it's a meinchat **plugin
  config** value, not a `.env` var).
- **`cbor2` was added to `requirements.txt`** but the docker image needs a
  **rebuild** (`make up-build`) for it to persist; it was installed inline for
  today's test runs.
- **`meinchat_plus` is intentionally NOT in `plugins.json`** (dormant) so the
  half-built plugin can't auto-load and break the app.

## 6. S28 is not finished — see the handoff

S28 Phase 2 (E2E encryption) is partially done: 3a complete, 3b started. The
full state + the exact next increment + all gotchas are captured in
[`../handoff-s28.md`](../handoff-s28.md) so tomorrow starts there.
