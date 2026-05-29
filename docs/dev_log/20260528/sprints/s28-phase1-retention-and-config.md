# S28 — Phase 1 master: retention, config, client cache (no crypto)

**Parent strategy doc:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
**Phase 2:** [s28-phase2-e2e-and-ios.md](s28-phase2-e2e-and-ios.md) — the E2E + iOS work; ships *after* phase 1.
**Decided 2026-05-28 (S28 decision R2-Q2):** phase 1 ships first
and independently. Phase 1 can land + verify without phase 2 even
being touched.

---

## 1. Goal (user value, no crypto)

Independent of the meinchat-plus E2E track, phase 1 makes meinchat
**operator-friendly + privacy-aware on its own merits**:

1. **Per-instance config** for retention windows + envelope size cap
   (S28.0). Admins tune via the meinchat plugin admin UI; no redeploy.
2. **Server retention prune** (S28.1) — daily cron deletes message
   rows older than `messages_retention_days_server` (default 2 days)
   and the matching attachment objects. The prune predicate is
   `IRetentionPolicy.should_prune(row, now)`; phase 1 ships only the
   `ConfigRetentionPolicy` default (plain rows). Phase 2's
   `E2eAwareRetentionPolicy` slots in via the same port without
   touching this slice.
3. **Encrypted-at-rest client cache** (S28.2) on web + iOS — 10-day
   TTL (shorten-only best-effort), KEK held in WebCrypto / Keychain.
   Cold-start paints conversation history before the server responds.

Lifts the operator-amnesia privacy risk **independently** of the
crypto track. Even if phase 2 never ships, prod's plaintext-leak
window shrinks from "forever" to "2 days" + every device gets an
offline-readable 10-day archive.

## 2. Phase 1 sub-sprints

| # | Sub-sprint | Repo touch | Backward compat? |
|---|---|---|---|
| 0 | [Config keys + `/limits` endpoint + iOS/web consumers](../done/s28-0-config-and-limits-endpoint.md) | meinchat (`vbwd-backend/plugins/meinchat`, `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`) | Yes — additive config + read-only GET |
| 1 | [Server retention prune (daily APScheduler)](../done/s28-1-server-retention-prune.md) | meinchat (backend only) | Yes — at 2-day default the prune is a real behavioural change on prod; documented in deploy notes |
| 2 | [Client local cache with 10-day TTL + at-rest encryption](../done/s28-2-client-local-cache.md) | meinchat (web + iOS) | Yes — purely additive |

**Dependencies:** S28.1 + S28.2 both consume the config keys S28.0
adds. Within phase 1: 0 first, then 1 + 2 in parallel.

## 3. Phase 1 does NOT include

- Any crypto. The `body` column stays plaintext; envelopes are not
  introduced yet.
- The S28.3a port extraction. That's phase 2 — phase 1 is happy with
  meinchat's existing internal seams.
- Any device directory / device-key concept.
- Capability discovery beyond `enabled_protocols: ["plain"]`. The
  `/capabilities` endpoint is added in phase 2's S28.3a.
- Message receipts (delivery + read dots). Backed by S28.3a's
  schema additions — ships in phase 2.

## 4. Phase 1 acceptance

- `/api/v1/messaging/limits` returns the four config keys; flipping
  any in the admin UI surfaces in the next call within seconds.
- Daily cron at 03:00 UTC deletes message rows older than
  `messages_retention_days_server`; idempotent re-run is a no-op.
- Attachments matching pruned rows are removed from `IFileStorage`
  best-effort; storage failures don't roll back the row delete.
- Web cold-start paints cached messages before the server responds
  (verified by network throttle in the e2e suite).
- iOS cold-start mirror.
- Raw filesystem read of the IDB store (web) / CoreData SQLite
  (iOS) does NOT contain plaintext body bytes of any cached row.
- `bin/pre-commit-check.sh --full` GREEN on backend; fe-user +
  iOS-plugin-meinchat package tests GREEN.

## 5. Phase 1 deploy notes

- **First prod run with `messages_retention_days_server = 2`** will
  delete most of vbwd.cc's existing chat history. Surface in the S28.1
  release notes; operators can pre-set the key to a larger value
  before the recipe rebuilds.
- **`messages_retention_days_server = 0` mode** is rejected at plugin
  enable IF meinchat-plus is also enabled. Phase 1 never has
  meinchat-plus enabled (it ships in phase 2), so 0-mode is allowed
  here; phase 2 enable will refuse if the operator left it at 0.

## 6. Phase 1 engineering-requirements check

- **TDD-first.** Each sub-sprint's RED test set is the gate.
- **DevOps-first.** Schema-free in S28.1; the schema additions are
  phase 2 (S28.3a). Phase 1 is alembic-clean.
- **NO OVERENGINEERING.** Three small, additive sub-sprints. No port
  extraction in this phase — phase 2 absorbs the refactor cost when
  there's a concrete consumer (meinchat-plus).
- **DRY.** Same `config_store.get_config("meinchat")` lookup powers
  the `/limits` route, the retention prune, and the client-cache
  TTL resolver. One source of truth.
- **Core agnostic.** Entirely in `plugins/meinchat/` + the two
  client plugin trees.

## 7. Ship-readiness vs vbwd.cc v1

Phase 1 is **release-ready before v1 launch** — none of its sub-sprints
depend on phase 2 work. Recommended to land + bake for one prod
deploy cycle BEFORE phase 2 begins:

- Prove the daily prune behaves on real prod data.
- Prove the encrypted-at-rest cache survives across browser versions
  and iOS OS updates.
- Get a baseline for "what does the storage footprint look like at
  2-day retention?"

Then phase 2 starts with confidence in the retention infrastructure
it depends on.

---

## Anchor

Inherits the binding engineering requirements at
[`_engineering_requirements.md`](_engineering_requirements.md).
Strategy / threat model / locked decisions live in
[`s28-meinchat-e2e-encryption-and-retention.md`](s28-meinchat-e2e-encryption-and-retention.md).
