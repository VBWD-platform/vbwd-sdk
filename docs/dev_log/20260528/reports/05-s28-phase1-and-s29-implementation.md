# Report 05 — S29 + S28 Phase 1 implemented (fe-user chrome flash, meinchat retention/config/cache)

**Date:** 2026-05-29
**Author:** implementation session (TDD agent discipline)
**Sprints closed:** [S29](../done/s29-fe-user-home-no-chrome-flash.md),
[S28.0](../done/s28-0-config-and-limits-endpoint.md),
[S28.1](../done/s28-1-server-retention-prune.md),
[S28.2](../done/s28-2-client-local-cache.md)
**Repos touched:** `vbwd-fe-user` (host + `plugins/meinchat`), `vbwd-backend/plugins/meinchat`
**Not committed** — left for user verification + commit per standing rule.

---

## 1. Summary

Four sprints implemented test-first and brought to a green quality gate.
S29 (fe-user chrome-flash) shipped as a scoped flash-only fix after the
code turned out to have moved past the sprint's assumptions. S28 **phase 1**
(config + retention prune + encrypted client cache, **no crypto/E2E**)
shipped complete across backend + web; iOS slices and all phase-2 work were
left for their own track. Three design forks surfaced and were resolved by
the user rather than guessed.

## 2. S29 — fe-user `/` no-chrome-flash

**Scope correction (important).** The sprint (2026-05-28) assumed `Home.vue`
did an inline async `/cms/routing-rules/middleware` fetch. By the time of
implementation (2026-05-29), a refactor had already moved that logic into a
CMS plugin router guard (`plugins/cms/src/routing/middlewareRoutingGuard.ts`),
and `Home.vue` was already the synchronous, rules-free redirect the sprint's
§3.2 was trying to create. So:

- **§3.1 (the real fix) landed:** `noLayout: true` on the `/` route meta in
  `vue/src/router/index.ts`. `App.vue:39` already short-circuits on it, so no
  `UserLayout` chrome paints around the empty redirect bouncer.
- **§3.2 was already done** by the prior refactor — dropped.
- **Sprint test #5** ("authed visitor skips the rules API") was **vacuous**
  (`Home.vue` no longer imports the api client) — dropped rather than assert
  a tautology.
- **Secondary intent deferred (user decision):** an active CMS `default` rule
  redirects an authenticated visitor at `/` to the public slug *before*
  `Home.vue` can route to `/dashboard` (the CMS guard has no auth check). The
  e2e proved this live. Honouring "authed → dashboard" now requires a CMS-guard
  change, which S29 §3.3 explicitly scoped out. User chose **primary
  flash-fix only**; the authed e2e asserts the actual guarantee (no chrome
  paints at `/`, never `/login`), not the destination.

**Files:** `vue/src/router/index.ts` (the flag),
`vue/tests/unit/router/home-route-meta.spec.ts` (pins it, RED→GREEN confirmed),
`vue/tests/e2e/valid-session-no-chrome-flash.spec.ts` (authed + anonymous).

**Gate:** `npm run test` 557 passed / 1 skipped; `npm run lint` 0 errors;
e2e 4 passed (2 new + the 2 no-regression `stale-session-no-flash` specs).
Grep oracle `noLayout: true` present at `router/index.ts:14`.

**Env note:** the dev DB was missing the `test@example.com` user (the
pre-existing `stale-session` spec failed identically at login); seeded via the
public `POST /api/v1/auth/register` (service layer, not raw SQL).

## 3. S28 Phase 1 — meinchat retention + config + cache

All work inside `plugins/meinchat/` (backend + fe-user); core stays agnostic.

### S28.0 — config keys + `/limits`
- 4 keys (`messages_retention_days_server`=2,
  `messages_retention_days_client_suggested`=10,
  `attachments_retention_days_server`=2, `ciphertext_max_bytes`=16384) in
  `DEFAULT_CONFIG` + `config.json` + `admin-config.json` (Retention tab).
- `GET /api/v1/messaging/limits` — **absolute path** (meinchat
  `get_url_prefix()` is `""`; the sprint's relative `/limits` pseudo-code was
  corrected), `@require_auth`, reads via the existing `_meinchat_config()`
  helper, standard `Plugin not enabled` 404 envelope. Returns the four
  operator knobs only — `enabled_protocols` deliberately excluded (moves to
  `/capabilities` in S28.3a).
- fe-user `useMessagingLimits.ts` (24h cache, error-preserves-data) +
  `MeinchatRetentionSection.vue` via `profileSectionsRegistry`; i18n in 8
  locales.
- **Deferred to phase 2:** sprint test #6 (`IncompatibleRetentionConfigError`
  refusal) — meinchat-plus does not exist yet; kept as a skip placeholder.

### S28.1 — server retention prune
- `IRetentionPolicy` port + `ConfigRetentionPolicy` (plain rows,
  threshold-based, negative days → `ValueError`). The port earns its keep as
  the meinchat→meinchat-plus extension seam.
- `RetentionService` — idempotent `prune_messages`/`prune_attachments`,
  injected repo/storage/policy/clock, frozen `RetentionResult`; attachment
  `IFileStorage.delete()` failures logged + counted, never propagated.
- `message_repository.find_older_than` + `delete_by_ids`.
- `scheduler.py` (mirrors booking/subscription), daily 03:00 UTC,
  `retention_prune_cron`-overridable, registered in `on_enable` **guarded by
  `if not current_app.config.get("TESTING")`** + a regression test — the
  connection-exhaustion lesson.
- **Deferred to phase 2:** `E2eAwareRetentionPolicy` and specs #9–#12 (need
  the `protocol` + `delivered_to_all_addressed_devices_at` columns S28.3a
  adds) — skip placeholders citing S28.3b; the `make meinchat-prune` target
  (avoids coupling the core Makefile to one plugin).

### S28.2 — web client local cache (at-rest encrypted)
- **KEK design fork resolved (user decision).** The sprint derives the cache
  KEK from S28.3b's device-pairing passphrase (Argon2id) — a phase-2 artifact.
  The cache is KEK-agnostic (`useLocalMessageCache(kek)`); only `loadKek()`
  differs by phase. **Phase 1 `loadKek()`** returns a device-bound
  **non-extractable** WebCrypto AES-GCM-256 key persisted as a `CryptoKey`
  object in IndexedDB (no passphrase) — satisfies the "no plaintext at rest"
  acceptance vs a filesystem adversary. **S28.3b swaps `loadKek.ts` only;** the
  cache API and all callers are untouched.
- `useLocalMessageCache.ts` (AES-GCM seal per row, `cached_at` outside the
  seal), `clientRetention.ts` `min(user, serverSuggested)` resolver,
  cache-first `openConversation`, 30-min `setInterval` eviction in
  `useMeinchatStore.boot()` (no Web Worker — trivial sweep), shorten-only
  numeric input in `MeinchatRetentionSection.vue`
  (`localStorage['meinchat.client_retention_days']`).
- Deps `idb` + `fake-indexeddb` added to `vbwd-fe-user` (host install;
  `package-lock.json` gained 18 lines, dropped no cross-platform binaries).
- At-rest no-plaintext + no-KEK-in-localStorage pinned as unit specs.

## 4. Quality gates (all green; no commits)

| Slice | Gate | Result |
|---|---|---|
| S29 | fe-user `npm run test` + `lint` + e2e | 557✓/1s, 0 errors, e2e 4✓ |
| S28.0 backend | `bin/pre-commit-check.sh --plugin meinchat` | A/B/C PASS |
| S28.0 web | fe-user `lint` + `test` | 0 errors, 562✓ |
| S28.1 | `bin/pre-commit-check.sh --plugin meinchat` | SUCCESS (179✓/5s unit, 6 integration) |
| S28.2 | fe-user `lint` + `test` | 0 errors, 579✓/1s |

Pre-existing black drift in 3 rate-limit-track meinchat files (S26/S27 work,
not this slice) was reformatted with user approval to get a fully green
`--plugin meinchat` gate; an unused `pytest` import was removed.

## 5. Phase-2 seams (so S28.3a/3b plug in cleanly)

- **`loadKek.ts`** is the only cache-crypto swap point (device-bound key →
  passphrase-Argon2id KEK).
- **`IRetentionPolicy`** port is in place; `E2eAwareRetentionPolicy` registers
  through it once S28.3a adds the schema columns.
- meinchat-plus 0-day refusal + the receipt-dot columns + capabilities
  endpoint remain phase-2.

## 6. Follow-ups / open items

- **S29 secondary:** decide whether authed visitors at `/` should bypass the
  CMS default rule to land on `/dashboard` (needs a CMS-guard auth-skip) — a
  small follow-up sprint if desired.
- **Manual acceptance not in the unit gate:** S28.2 network-throttle
  cold-start paint (send 5 → reopen → paints before server) — worth one
  eyeball before prod.
- **Commit** the two plugin repos + `vbwd-fe-user` (the dep additions) and S29
  after verification.
