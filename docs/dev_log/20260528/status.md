# 2026-05-28 — Daily status

## Theme

Stop the 429s on vbwd.cc, then plan the meinchat security uplift
(E2E + retention). Two prod regressions on the chat screen — one
meinchat-specific (`new_conversation` counter triggered on every open),
one cross-cutting (Flask-Limiter global cap at 10 000/day/IP) — landed
as separate sprints and verified live. Privacy & retention design is
the next slice (S28).

## Sprint index

| # | Sprint | Area | Status |
|---|--------|------|--------|
| 26 | [Meinchat rate limits — count creates only + iOS overrides + admin-configurable](done/s26-meinchat-rate-limits.md) | `vbwd-backend` / `plugins/meinchat` | **Done — IMPLEMENTED & VERIFIED 2026-05-28** ([report](reports/02-s26-meinchat-rate-limits-complete.md)) |
| 27 | [Lift the global Flask-Limiter ceilings (env-configurable)](done/s27-lift-global-flask-limiter.md) | `vbwd-backend` core | **Done — IMPLEMENTED & VERIFIED 2026-05-28** ([report](reports/03-s27-lift-global-flask-limiter-complete.md)) |
| 28 | [Meinchat extension seams + meinchat-plus (Signal ratchet) + retention (10d clients / 2d server)](sprints/s28-meinchat-e2e-encryption-and-retention.md) | meinchat (`vbwd-backend`/`plugins/meinchat`, `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`) **+ new** `meinchat-plus` (3 new plugin repos) | **Planned — 2026-05-28** |

## Work done today

- **Sprint 26 — meinchat rate limits.**
  - `POST /api/v1/messaging/conversations` is now true start-or-get: it
    consults `ConversationService.find_between` first and counts against
    the `new_conversation` quota only when a brand-new row is actually
    inserted.
  - New `services/rate_limit_policy.py` resolves the per-category cap
    against the current request's `X-Client-Platform` header — iOS /
    macOS get higher ceilings (60 / 90 / 120 / 30 per their windows),
    web baseline unchanged.
  - All four meinchat rate-limit categories (`new_conversation`,
    `nickname_search`, `message_send`, `attachment_send`) are now
    admin-configurable per instance via 16 keys in the plugin
    `config.json` + `admin-config.json`.
  - 32/32 sprint specs green, `bin/pre-commit-check.sh --quick` GREEN.
  - Full report: [`reports/02-s26-meinchat-rate-limits-complete.md`](reports/02-s26-meinchat-rate-limits-complete.md).

- **Sprint 27 — global Flask-Limiter ceilings.**
  - Extracted `_global_default_limits()` from `vbwd/extensions.py` —
    reads `RATELIMIT_DEFAULT_DAY` (default **100 000**, 10× lift) and
    `RATELIMIT_DEFAULT_HOUR` (default **20 000**, 10× lift). Zero
    disables a window; non-integer crashes startup (fail-fast).
  - `.env.example` documents the four ops knobs in one place.
  - 12 new/extended specs (9 env-driven + 3 contract preservation),
    `bin/pre-commit-check.sh --full` GREEN — 2228 unit + 366 integration.
  - 429 response shape unchanged (Liskov on the wire).
  - Full report: [`reports/03-s27-lift-global-flask-limiter-complete.md`](reports/03-s27-lift-global-flask-limiter-complete.md).

- **Sprint 28 — meinchat extension seams + meinchat-plus (Signal ratchet) + retention (drafted).**
  - **Two-track delivery.** First refactor `meinchat` so it works alone
    *and* serves as a base for downstream plugins — extract narrow ports
    with identity/null defaults so meinchat-alone behaviour is unchanged.
    Then ship `meinchat-plus` as a separate plugin that registers the
    Signal-ratchet `IBodyCodec` + `IDeviceDirectory` against those ports.
  - **Constellation A chosen** (Signal-style double-ratchet). B and C
    documented in the trade matrix for the record.
  - **Defaults:** server `2` days / client `10` days; client retention
    is **shorten-only** (cannot extend beyond the server's suggestion).
  - **Admin-configurable** per-instance via meinchat's plugin
    `config.json` + `admin-config.json`.
  - **`GET /api/v1/messaging/limits`** endpoint feeds iOS + web + future
    native shells — zero hard-coded retention numbers on any client.
  - **No `meinchat-enterprise` in this sprint.** Headroom is left in the
    port surface so it could be built later as a third plugin; not
    drafted now.
  - **6 sub-sprints**, one detailed dev plan per file:
    - [S28.0](sprints/s28-0-config-and-limits-endpoint.md) — config keys + `/limits` endpoint + iOS/web consumers.
    - [S28.1](sprints/s28-1-server-retention-prune.md) — server retention prune (daily APScheduler).
    - [S28.2](sprints/s28-2-client-local-cache.md) — client local cache with 10-day TTL + shorten-only UI.
    - [S28.3a](sprints/s28-3a-meinchat-extension-ports.md) — meinchat extension ports + schema concessions + capability endpoints (refactor; "plugin-free still works" oracle).
    - [S28.3b](sprints/s28-3b-meinchat-plus-signal-ratchet.md) — `meinchat-plus` (Signal ratchet + device directory + prekey bundles), 3 new plugin repos.
    - [S28.4](sprints/s28-4-attachment-encryption.md) — attachment encryption (mirror of S28.3 on the file-write/read path).

## Verification

- **Unit:** 2228 passed in `vbwd-backend` (+50 from S26+S27).
- **Integration:** 366 passed, 3 skipped.
- **Lint / mypy / black:** 0 errors.
- **End-to-end live:** open `@lololo` 100× → all 200 (S26); 7 × GET / with
  `RATELIMIT_DEFAULT_DAY=5` → 5 × 302 → 429 → 429 (S27, env honoured).

## Pending — needs user action

- **Confirm the six remaining S28 open decisions** in
  [`sprints/s28-…#11-open-decisions-still-pending`](sprints/s28-meinchat-e2e-encryption-and-retention.md#11-open-decisions-still-pending):
  strict fallback when a peer has no device key, iOS key-storage class,
  pipeline-port arity matrix, schema discriminator approach, optional
  iOS storage-class toggle, prekey-bundle table at slice 3b or later.
  Each has a recommendation; a single "agree to all" lets slice 0
  start. (Defaults `2`/`10` + Constellation A + shorten-only are
  already locked in.)

## Blockers

None blocking S26/S27 ship. S28 is design-only until the six remaining
open decisions in §11 of the sprint are voted on.
