# 2026-05-28 — Daily status

> **➡️ Active status moved to [`../20260530/status.md`](../20260530/status.md)** (2026-05-30).
> The still-PLANNED/DRAFT sprints (S30–S37, S40–S42, S28.6/7) were carried into
> `../20260530/sprints/`; this folder keeps the resolved S26/S27/S28(web)/S29/S38
> work + the S28 epic strategy docs + S39.
> **Resume from [`handoff-s28.md`](handoff-s28.md)** (S28 E2E track).
> End-of-day wrap-up: [`reports/07-daily-wrapup-2026-05-29.md`](reports/07-daily-wrapup-2026-05-29.md).

## Theme

Stop the 429s on vbwd.cc, then plan the meinchat security uplift
(E2E + retention). Two prod regressions on the chat screen — one
meinchat-specific (`new_conversation` counter triggered on every open),
one cross-cutting (Flask-Limiter global cap at 10 000/day/IP) — landed
as separate sprints and verified live. Privacy & retention design (S28,
revised after a critical review) is the next slice. Plus a fe-user
chrome-flash fix (S29), load-test harness corrections (S30), and five
follow-ups off the rate-limit work (S31–S35).

## Sprint index

| # | Sprint | Area | Status |
|---|--------|------|--------|
| 26 | [Meinchat rate limits — count creates only + iOS overrides + admin-configurable](done/s26-meinchat-rate-limits.md) | `vbwd-backend` / `plugins/meinchat` | **Done — IMPLEMENTED & VERIFIED 2026-05-28** ([report](reports/02-s26-meinchat-rate-limits-complete.md)) |
| 27 | [Lift the global Flask-Limiter ceilings (env-configurable)](done/s27-lift-global-flask-limiter.md) | `vbwd-backend` core | **Done — IMPLEMENTED & VERIFIED 2026-05-28** ([report](reports/03-s27-lift-global-flask-limiter-complete.md)) |
| 28 | [Meinchat extension seams + meinchat-plus (Signal ratchet) + retention (10d clients / 2d server)](sprints/s28-meinchat-e2e-encryption-and-retention.md) — strategy index, split into **[Phase 1](sprints/s28-phase1-retention-and-config.md)** (retention + config + cache) + **[Phase 2](sprints/s28-phase2-e2e-and-ios.md)** (E2E + iOS) | meinchat (`vbwd-backend`/`plugins/meinchat`, `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`) **+ new** `meinchat-plus` (3 new plugin repos, **public from day one**) **+ iOS app update + iOS meinchat-plus plugin (enabled at v1 launch)** | **Phase 1 DONE — IMPLEMENTED & GREEN 2026-05-29** (backend + web; iOS deferred): [S28.0](done/s28-0-config-and-limits-endpoint.md) · [S28.1](done/s28-1-server-retention-prune.md) · [S28.2](done/s28-2-client-local-cache.md) ([report 05](reports/05-s28-phase1-and-s29-implementation.md)). **Phase 2 IN PROGRESS:** [S28.3a](done/s28-3a-meinchat-extension-ports.md) ✅ DONE & GREEN 2026-05-29 (backend: ports/registry + e2e schema + capabilities + negotiation; 241 specs). [3b](done/s28-3b-meinchat-plus-signal-ratchet.md) (meinchat-plus, new plugin) **BACKEND DONE & GREEN 2026-05-29** — 4 models + migration, 3 repos (one-time consume `FOR UPDATE SKIP LOCKED`), device directory + signed/one-time prekey services (Ed25519 verify; concurrent-consume race spec), policy/capability/`MarkDeliveryAttempted`/`E2eAwareRetentionPolicy`, `ProtocolAwareCodec` (plain↔e2e dispatch), 6 device/prekey routes, full `on_enable`/`on_disable`; **49 unit + 7 integration green; `--plugin meinchat_plus --full` GREEN** ([report 08](reports/08-s28-3b-backend-persistence.md)). **ENABLED 2026-05-29** in plugins.json/config.json after the **meinchat-wiring slice** (send `expected_device_ids` + `envelope_b64`, GET delivery hook, scheduler `IRetentionPolicy` resolution) — **full e2e server round-trip green** ([report 09](reports/09-s28-3b-meinchat-wiring-and-enable.md)); meinchat `--full` + meinchat_plus `--full` both GREEN. Remaining: fe-user + iOS client crypto (libsignal). **S28.4 (attachment enc) increment 1 DONE & green 2026-05-29** — server ciphertext storage layer: `meinchat_attachment` child table + migration (additive) + `AttachmentRepository` + `AttachmentService.store_encrypted`/`read_blob` (server stores opaque blobs, never decodes/resizes); 6 unit + 4 integration; meinchat `--full` GREEN ([report 10](reports/10-s28-4-attachment-encryption-storage.md)). **Increment 2 DONE & green** — e2e attachment routes (`POST /messages/<id>/attachments`, `GET /attachments/<id>`) + `Message.to_dict() attachments[]` (additive) + `add_e2e_attachment`/`get_attachment_blob`; 7 unit + 2 integration round-trip; both gates GREEN ([report 11](reports/11-s28-4-attachment-routes-and-to-dict.md)). **Increments 3+4 DONE & green** ([report 12](reports/12-s28-4-schema-unification-and-fe-migration.md)): retention prunes child blobs; ALL attachments folded into `meinchat_attachment` (plain `send_attachment` writes fullres+thumb child rows; +nullable width/height); legacy `message.attachment_*` columns DROPPED (migration `20260603_1000`, **no backfill — pre-rollout**); `to_dict` emits only `attachments[]`; fe-user + fe-admin migrated to `attachments[]` (plain renders, e2e shows 🔒). Backend meinchat/meinchat_plus `--full` GREEN; fe-user 68 + fe-admin 4 specs GREEN. **iOS client must migrate to `attachments[]`** (iOS agent). **Remaining S28.4 = increment 5 (client crypto, greenfield, SCOPED/deferred)**: fe-user libsignal plugin + iOS (iOS agent). |
| 29 | [fe-user `/` no-chrome-flash on return with a valid JWT](done/s29-fe-user-home-no-chrome-flash.md) | `vbwd-fe-user` (host app `vue/src/`) | **Done — IMPLEMENTED & GREEN 2026-05-29** ([report 05](reports/05-s28-phase1-and-s29-implementation.md)). Shipped as the scoped **flash-fix only** (`noLayout:true` on `/`) — a prior CMS-guard refactor already did §3.2. **Secondary deferred:** authed-`/`→`/dashboard` needs a CMS-guard auth-skip (out of S29 scope). |
| 30 | [Heavy-load test harness fixes (workflow + Locust scenario)](sprints/s30-heavy-load-harness-fixes.md) **+** [Backend code affordances for robust load testing (`flask seed` CLI + `_routes` + `_seed_status`)](sprints/s30-load-test-code-affordances.md) | `VBWD-platform/vbwd-platform` + `vbwd-backend` core | **Planned — 2026-05-28** (triggered by [report 04 — heavy-load](reports/04-heavy-load-26452905684-harness-drift.md)) |
| 31 | [Flask-Limiter per-user keying (NAT-shared bucket fix)](sprints/s31-flask-limiter-per-user-keying.md) | `vbwd-backend` core | **Planned — 2026-05-28**. Follow-up to S27. **Open: keyfunc design must verify JWT signature** (critical review found a DoS-via-forged-JWT vector if signature is skipped). Release-blocker once that is resolved. |
| 32 | [macOS rate-limit overrides (meinchat)](sprints/s32-macos-rate-limit-overrides.md) | `vbwd-backend` / `plugins/meinchat` | **Planned — 2026-05-28**. Follow-up to S26 — only matters when Mac Catalyst client ships; non-blocker for v1. |
| 33 | [429 telemetry (structured WARN log on every rate-limit trip)](sprints/s33-429-telemetry.md) | `vbwd-backend` core + `plugins/meinchat` | **Planned — 2026-05-28**. Strongly recommended before v1 release — observability for S26/S27. |
| 34 | [Drop legacy meinchat rate-limit config keys (DEFERRED)](sprints/s34-drop-legacy-meinchat-rate-keys.md) | `vbwd-backend` / `plugins/meinchat` | **DEFERRED — DO NOT IMPLEMENT YET.** Gated on S26 reaching prod everywhere + one deploy cycle elapsing without meinchat-rate-limit regressions. |
| 35 | [iOS: cache conv_id from inbox, drop 429-retry loop](sprints/s35-ios-cache-conv-id-drop-retry.md) | `vbwd-ios/VBWD/Packages/vbwd-ios-plugin-meinchat` | **Planned — 2026-05-28**. iOS app re-release track; couples to whatever iOS release follows. |
| 36 | [Discounts & coupons at checkout (wire the island into both checkouts)](sprints/s36-discounts-at-checkout.md) | `vbwd-backend` (core seam + `plugins/{discount,subscription,shop}`) · `vbwd-fe-core` · `vbwd-fe-user` · `vbwd-fe-admin` (e2e) | **Planned — 2026-05-28**. Diagnosis: discount backend plugin + fe-admin CRUD ship, but the **consumer checkout path was never built** — no coupon input in either checkout, neither checkout endpoint accepts/applies `coupon_code`, the discount plugin is an island reachable only via `POST /api/v1/coupons/validate`. Wires it end-to-end via a generic core price-adjustment port (agnostic) + a reusable fe-core `CouponInput`; proves it with Playwright (public + private checkout redeeming seeded codes) + seeder-seeds-on-install assertions + an admin-injection→user-checkout e2e. **3 open product Qs.** |
| 37 | [fe-user "Pay Zero" checkout (port the iOS zero-cost flow, both checkouts)](sprints/s37-fe-user-pay-zero-checkout.md) | `vbwd-fe-core` · `vbwd-fe-user` (no backend change) | **Planned — 2026-05-28**. iOS already does it (`CheckoutViewModel.isZeroTotal` → hide payment selection, "Pay Zero" button, notice) and the **backend already auto-pays a zero-total checkout** (`checkout_handler.py:250` emits `PaymentCapturedEvent`/`zero-price`). Only the fe-user UI branch is missing. Adds one core-store `isZeroTotal` computed + a shared fe-core `ZeroTotalNotice`, consumed identically by the **public and private** checkouts; Playwright proves both. Couples to S36 (100%-discount-to-zero takes the same path). **3 open product Qs.** |
| 38 | [meinchat SSE event bus — one Redis connection per worker + fail-loud backend](done/s38-meinchat-redis-bus-hardening.md) | `vbwd-backend` / `plugins/meinchat` | **Done — IMPLEMENTED & GREEN 2026-05-29** ([report 06](reports/06-sse-worker-starvation-and-redis-bus-hardening.md)) — 36 event-bus specs incl. cross-worker delivery + connection-count; full meinchat 206 passed; lint/mypy clean. Follow-up to the prod-freeze hotfix (gunicorn `sync`→`gthread`, SSE lifetime cap + DB-conn release — **applied & verified green 2026-05-29**). Hotfix raised the concurrent-stream ceiling ~4→~256, amplifying a latent flaw: `RedisEventBus` opens **one Redis connection per stream** (`redis_event_bus.py:81`); also `_event_bus()` **silently+stickily falls back** to the broken in-process bus on a transient Redis blip (`routes.py:196`). Refactors to one listener thread per worker fanning into the shared queue subscription (DRY), decides the backend once+loud (no silent degrade), adds the missing tests (cross-worker delivery + connection-leak). **3 open Qs.** |

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
  - **8 sub-sprints** (all revised 2026-05-28 to absorb a critical
    review — server-side encryption → client-side; ports trimmed 12 → 6;
    capability endpoints 3 → 1; padding + prekey-race + downgrade fixes;
    at-rest cache encryption resolved):
    - [S28.0](sprints/s28-0-config-and-limits-endpoint.md) — config keys + `/limits` endpoint + iOS/web consumers.
    - [S28.1](sprints/s28-1-server-retention-prune.md) — server retention prune (E2E-aware: exempts undelivered ciphertext from the prune).
    - [S28.2](sprints/s28-2-client-local-cache.md) — client local cache with 10-day TTL + **at-rest encryption** under a wrapped Keychain/WebCrypto key.
    - [S28.3a](sprints/s28-3a-meinchat-extension-ports.md) — meinchat **six** extension ports + schema concessions + unified `/capabilities[?me=true]` endpoint + negotiation-failure error contract.
    - [S28.3b](done/s28-3b-meinchat-plus-signal-ratchet.md) — `meinchat-plus` (**client-encrypts** Signal ratchet + split `signed_prekey` / `one_time_prekey` tables + `FOR UPDATE SKIP LOCKED` consume + 256B padding + downgrade fail-closed + delivery tracking), 3 new plugin repos. **Backend done & green 2026-05-29.**
    - [S28.4](done/s28-4-attachment-encryption.md) — attachment encryption (client encrypts; new `meinchat_attachment` child table with `kind` enum for fullres + thumb dual blobs). **Done & green 2026-05-30** (backend storage+routes, fe-reader migration, client hybrid crypto). UI glue remains.
    - [S28.6](sprints/s28-6-ios-meinchat-app-update-plan.md) — **iOS app update** (capabilities discovery + at-rest-encrypted local cache + retention UI), additive only; beta-RC safe.
    - [S28.7](sprints/s28-7-ios-meinchat-plus-plugin-plan.md) — **new `vbwd-ios-plugin-meinchat-plus`** (Signal client + device pairing + downgrade fail-closed), disabled-by-default in beta-RC TestFlight.

- **Sprint 29 — fe-user `/` no-chrome-flash (drafted).**
  - Two narrow additive edits: `noLayout: true` meta on `/` route (DRY
    win — App.vue already short-circuits on the flag) +
    synchronous `isAuthenticated() → router.replace('/dashboard')` in
    `Home.vue` ahead of the rules fetch.
  - No backend, no core, no plugin contract change.
  - **Open product question** (raised by review): is the CMS default
    routing rule intended for anonymous visitors only, or for all
    visitors? §3.2 assumes anonymous-only — if all-visitors is the
    intent, §3.1 alone (route-meta flag) is the right scope; §3.2's
    destination short-circuit would be a behaviour change wearing a
    bugfix's clothes.
  - Triggered by [`reports/04-cms-routing-flash-of-dashboard-on-return.md`](reports/04-cms-routing-flash-of-dashboard-on-return.md).

- **Sprint 30 — load-test harness + backend affordances (drafted).**
  - Triggered by [`reports/04-heavy-load-26452905684-harness-drift.md`](reports/04-heavy-load-26452905684-harness-drift.md).
  - Two coordinated sprints: [s30-heavy-load](sprints/s30-heavy-load-harness-fixes.md)
    fixes the GitHub Actions Locust scenario + `populate_db.py` for 8
    plugins; [s30-load-test-code-affordances](sprints/s30-load-test-code-affordances.md)
    adds backend hooks (`flask seed` CLI, `_routes`, `_seed_status`)
    so the harness has a stable contract to call.

- **Sprints 31–35 — rate-limit follow-ups (drafted off the critical review of S26/S27).**
  - [S31 per-user keying](sprints/s31-flask-limiter-per-user-keying.md):
    replace `get_remote_address` with a keyfunc that prefers
    `f"user:{jwt.user_id}"`, IP-keys only unauthenticated routes.
    Eliminates NAT-shared-bucket bug class. **Critical-review finding
    open:** the keyfunc as drafted skipped signature verification;
    that lets an attacker forge a JWT carrying a victim's user_id and
    DoS the victim's bucket. Must verify HS256 signature in the
    keyfunc before this lands. Release-blocker once that is resolved.
  - [S32 macOS rate-limit overrides](sprints/s32-macos-rate-limit-overrides.md):
    8 `rate_macos_*` keys + new admin tab; trivial. Non-blocker
    until Mac Catalyst client ships.
  - [S33 429 telemetry](sprints/s33-429-telemetry.md): single WARN log
    line per trip (route + bucket key + descriptor for Flask-Limiter;
    category + user + platform for meinchat). Strongly recommended
    before v1 release — without it the next "users hit the cap" report
    is screenshot-driven again.
  - [S34 drop legacy meinchat rate-limit keys](sprints/s34-drop-legacy-meinchat-rate-keys.md):
    **DEFERRED** — gated on S26 in prod everywhere + one deploy cycle.
  - [S35 iOS conv_id caching + drop 429-retry](sprints/s35-ios-cache-conv-id-drop-retry.md):
    plumb `conv.id` through `/meinchat/<nick>?conv=<id>`; drop the
    `ConversationViewModel.swift:61-66` exp-backoff retry loop.
    Couples to iOS release-train.

## Work done 2026-05-29 (implementation — S29 + S28 Phase 1)

Full write-up: [`reports/05-s28-phase1-and-s29-implementation.md`](reports/05-s28-phase1-and-s29-implementation.md).
Implemented test-first under the TDD-agent discipline; **not committed**
(left for user verification per standing rule).

- **S29 — fe-user no-chrome-flash → DONE & green.** Shipped scoped to the
  flash fix only: `noLayout: true` on the `/` route (`App.vue:39` already
  short-circuits on it). A prior CMS-guard refactor had already implemented
  §3.2's synchronous redirect, so that half was dropped; sprint test #5 was
  vacuous (`Home.vue` no longer imports the api) and dropped. **CMS-default-rule
  product question resolved:** authed-`/`→`/dashboard` is blocked by the CMS
  guard's `default` rule (no auth check) and needs a CMS-guard auth-skip —
  out of S29 scope, deferred. Gate: 557✓/1s unit, 0 lint errors, e2e 4✓
  (incl. the 2 no-regression stale-session specs).
- **S28.0 — config + `/limits` → DONE & green.** 4 retention/size keys
  (`DEFAULT_CONFIG`+`config.json`+`admin-config.json` Retention tab);
  `GET /api/v1/messaging/limits` (absolute path; four operator knobs only);
  fe-user `useMessagingLimits` + `MeinchatRetentionSection` via
  `profileSectionsRegistry` (8 locales). `--plugin meinchat` A/B/C PASS;
  fe-user lint+test green.
- **S28.1 — server retention prune → DONE & green.** `IRetentionPolicy` port +
  `ConfigRetentionPolicy`; idempotent `RetentionService` (injected
  repo/storage/policy/clock, attachment failures logged-not-raised);
  `find_older_than`/`delete_by_ids`; `scheduler.py` daily 03:00 UTC with the
  **`TESTING` guard** + regression test. `--plugin meinchat` SUCCESS
  (179✓/5s unit, 6 integration).
- **S28.2 — web client cache → DONE & green.** Encrypted IndexedDB cache;
  **phase-1 device-bound KEK** via `loadKek()` (non-extractable WebCrypto key
  in IDB — S28.3b swaps this file only for the passphrase-Argon2id KEK);
  cache-first `openConversation`; 30-min eviction sweep; shorten-only setting.
  Added `idb`+`fake-indexeddb`. fe-user lint 0 errors, 579✓/1s.
- **Phase-2 deferrals (correct — schema/plugin don't exist yet):**
  meinchat-plus 0-day refusal (S28.0 #6 / S28.1 #12), `E2eAwareRetentionPolicy`
  + specs #9–#11, `make meinchat-prune`, the `loadKek()` passphrase swap.
- **Housekeeping:** s29 + s28-0/1/2 moved to `done/`; pre-existing black drift
  in 3 rate-limit-track meinchat files reformatted (user-approved) for a green
  gate; unused `pytest` import removed.

## Work done 2026-05-29 (session 2 — S28.3b meinchat-plus backend)

Full write-up: [`reports/08-s28-3b-backend-persistence.md`](reports/08-s28-3b-backend-persistence.md).
Strictly TDD; **not committed** (plugins are gitignored in vbwd-backend → on-disk only).

- **S28.3b backend persistence → DONE & green** (handoff §3 steps 1–8). In
  `vbwd-backend/plugins/meinchat_plus/`: 4 models + migration
  `20260601_1000_meinchat_plus` (alembic path registered; "one active signed
  prekey per device" = **partial unique index**, no `btree_gist`); 3 repos
  (one-time consume `FOR UPDATE SKIP LOCKED`, BYTEA→bytes); `UserDeviceKeyDirectory`,
  `SignedPrekeyService` (Ed25519 verify via `cryptography`, injectable verifier,
  rotation supersedes), `OneTimePrekeyService` (**concurrent-consume race spec
  green**); `BothPeersHaveDeviceKeys`/`E2eV1Capability`/`MarkDeliveryAttempted`/
  `E2eAwareRetentionPolicy`; **`ProtocolAwareCodec`** (the registered IBodyCodec
  dispatches plain→Identity, e2e_v1→Validator so enabling never breaks plaintext);
  6 device/prekey routes; full `on_enable`/`on_disable`.
- **Gate:** `bin/pre-commit-check.sh --plugin meinchat_plus --full` **GREEN**
  (49 unit + 7 integration). meinchat unchanged **241/5**; both suites together
  **290 passed / 5 skipped** — no registry cross-leakage.
- **Plugin kept DORMANT** (not in `plugins.json`): global enable would register
  `E2eV1Capability` and break meinchat's S28.3a oracle
  `test_default_registry_returns_plain` (asserts exactly `{"server":["plain"]}`).
  Route/integration specs activate it hermetically via the `enabled_plugin`
  fixture (gate-patch + registry wiring + full teardown reset).
- **Deferred to the meinchat-wiring slice (next):** (1) meinchat send/negotiation
  route populates `SendContext.expected_device_ids` + accepts `envelope_b64`;
  (2) `scheduler.py` resolves `IRetentionPolicy` from the registry; (3) flip the
  meinchat capability/negotiate oracles to expect `e2e_v1` when meinchat-plus is
  enabled. THEN add `meinchat_plus` to plugins.json/config.json + the full
  client↔client round-trip (four §2.10 ciphertext assertions). Then **S28.4**.
- **Gate gotcha:** rebuild BOTH `test` AND `test-integration` compose images for
  `cbor2` (separate images off the same `Dockerfile.test`) or Part C fails
  `ModuleNotFoundError: cbor2`.
- **Housekeeping:** `s28-3b` sprint moved `sprints/ → done/`.

## Work done 2026-05-29 (session 3 — meinchat-plus repo extraction + fe client crypto)

- **3 private repos created** under `VBWD-platform` (visibility: private for now,
  per the session decision — diverges from the locked "public from day one"
  until crypto is finished): `vbwd-plugin-meinchat-plus` (backend),
  `vbwd-fe-user-plugin-meinchat-plus` (web), `vbwd-fe-admin-plugin-meinchat-plus`
  (admin). iOS is developed in the separate iOS app — **not built here**.
- Backend plugin dir got a `.gitignore` + `README.md` (prep for seeding). **No
  git init/commit/push performed yet** (deferred per user).
- **fe-user `meinchat-plus` crypto plugin — BUILT & green** (26 vitest specs,
  eslint clean) — [report 13](reports/13-meinchat-plus-repos-and-fe-user-crypto.md).
  `@signalapp/libsignal-client` is Node-native (not browser-safe) → audited
  pure-JS primitives (`@noble/curves`/`@noble/ciphers`/`@noble/hashes` + `hash-wasm`
  Argon2id + `cbor-x`). Implements X3DH + Double Ratchet (forward secrecy,
  tamper-detect, fan-out, own-device decrypt), 256B padding, CBOR envelope
  matching the server validator, passphrase KEK, downgrade fail-closed, key
  registration. *Ratchet is in-order (no skipped-key cache) → flagged for crypto
  audit.* **Not yet wired** into the meinchat store UI (needs a store seam).
- **fe-admin `meinchat-plus`** scaffolded + tested (3 specs): device-key view only
  (E2E → no content inspector).
- **Recipes** (`ci-status.sh`, `push-plugins.sh`) wired for the 3 new repos.
- **Git push DEFERRED** (per user): repos exist empty; all code on disk. iOS NOT
  built (separate app). **iOS must migrate to `attachments[]`** (backend dropped
  `attachment_url`).
- **Store crypto wiring DONE & green 2026-05-30** ([report 14](reports/14-meinchat-store-crypto-wiring.md)):
  crypto-provider seam in the meinchat store (`messageCryptoRegistry`); backend
  conversation serializer emits `protocol` (additive); `sendText` routes e2e via
  the provider (fail-closed without one); `_hydrateE2eRows`/`_decryptInPlace`
  decrypt e2e rows for display on read + SSE; `MeinchatPlusProvider` (fan-out
  encrypt + own-slot decrypt) + `registerCryptoProvider` hook. **All gates green:
  backend meinchat/meinchat_plus `--full`; fe-user 102 specs, eslint clean.**
- **SessionStore (last crypto layer) DONE & green 2026-05-30** ([report 15](reports/15-meinchat-plus-session-store.md)):
  prekey-message header carries X3DH init; `SessionManager.ensureOutbound`
  (X3DH-from-bundle, sig-verified) + `establishInbound` (responder cold-start,
  same-SK proven); provider cold-start wiring; ratchet-state serialize +
  **KEK-sealed IndexedDB** persistence (`createIdbKeyValueStore`). **Full
  no-prior-session bidirectional round-trip green.** fe-user **111 specs**,
  eslint clean.
- **Pairing flow DONE & green 2026-05-30** ([report 16](reports/16-meinchat-plus-pairing-flow.md)):
  `device-store.ts` (device material sealed under KEK + salt) + `pairing.ts`
  (`pairNewDevice`/`unlockDevice`/`isPaired`/`lock`/`saveSessions`). pair → send →
  persist → unlock → receive **end-to-end green**; wrong passphrase rejected.
  fe-user **114 specs**, eslint clean. **meinchat-plus web crypto is feature-complete.**
  Remaining = UI glue only (passphrase prompt wiring `pairNewDevice`/`unlockDevice`
  with `createIdbKeyValueStore` + the api module; composer/attachment UI) + hardening
  (ratchet skipped-key cache + audit, spk rotation/multi-device) + git push.
- **S28.4 attachment client crypto DONE & green 2026-05-30** — `crypto/attachment.ts`
  hybrid (one ChaCha20-Poly1305 blob + per-recipient ratchet-wrapped key envelope):
  `encryptAttachment`/`decryptAttachment`; 2-device fan-out + tamper specs (fe-user
  **118 specs**, eslint clean). Completes S28.4 §3 crypto → **sprint moved
  `sprints/ → done/`**. UI glue (image picker → encrypt → upload; download →
  decrypt → render) remains, same as the text composer.
- **Composer precheck DONE & green 2026-05-30** (spec §3.7) — `composer-precheck.ts`
  `precheckPeerSecureChat` (peer has no active device → block Send + hint; transient
  lookup error → optimistic enable + flag); 4 specs.
- **Vue glue building blocks DONE & green 2026-05-30** ([report 17](reports/17-meinchat-plus-vue-glue.md)):
  `usePairing` state machine + `PairingSheet.vue` (passphrase prompt) + `useComposerPrecheck`
  + attachment transport (`uploadAttachment`/`downloadAttachment` api + `encryptAndUploadAttachment`/
  `downloadAndDecryptAttachment` round-trip). fe-user **136 specs**, eslint clean; all exported from
  `index.ts`.
- **App-level view wiring DONE & green 2026-05-30** ([report 18](reports/18-meinchat-plus-view-wiring.md)):
  meinchat UI seams (`conversationExtensions` overlay + composer-precheck registries, core-agnostic);
  `ConversationView` renders the overlay + runs the precheck (guarded → meinchat-alone unaffected);
  meinchat-plus `SecureChatGate.vue` (pairing prompt for e2e until ready; persists sessions on tab-hide)
  + `activate()` registers overlay/precheck. fe-user **145 specs**, eslint clean. **TEXT E2E IS NOW
  WIRED END-TO-END** (pair via gate → encrypted send → decrypted read; Send disabled for device-less peer).
- **Attachment image UI DONE & green 2026-05-30** ([report 19](reports/19-meinchat-plus-attachment-image-ui.md)):
  provider `sendEncryptedImage` (client-resize → encrypt fullres → upload; local preview) + `hydrateRow`
  (decrypt text THEN attachment IN ORDER → body + blob URLs); `store.sendAttachment` e2e route (fail-closed);
  `_hydrateE2eRows`/`_decryptInPlace` use hydrateRow; `MessageBubble` renders e2e image from `attachmentUrls`.
  **v1 uploads fullres only** (one ratchet msg/image — no thumb to desync the in-order ratchet). fe-user
  **151 specs**, eslint clean. **meinchat-plus WEB CLIENT IS FEATURE-COMPLETE — text + image E2E work
  end-to-end through the UI.** Remaining = hardening only (skipped-key cache [re-enables e2e thumbs] +
  crypto audit + spk rotation/multi-device) + git push 3 repos (deferred). iOS = separate app.

## Work done 2026-05-30 (session 4 — meinchat-plus hardening + crypto audit + e2e smoke)

Full write-up: [`reports/20-meinchat-plus-hardening-audit-e2e.md`](reports/20-meinchat-plus-hardening-audit-e2e.md).
The "outstanding hardening + ops" list cleared. **Not committed** (deferred per user).

- **Ratchet skipped-message-key cache (Signal MKSKIPPED) DONE & green** — `crypto/ratchet.ts`
  `RatchetState.skipped` map (serialized), `trySkippedMessageKey`/`skipMessageKeys`, `ratchetDecrypt`
  rewritten to tolerate out-of-order + cross-DH-ratchet skips, bounded by `MAX_SKIP=1000` (rejects a
  malicious huge-`n`). 4 specs (out-of-order, cross-ratchet, single-use replay, MAX_SKIP guard).
- **E2E thumbnails re-enabled** — `sendEncryptedImage` now uploads BOTH fullres + thumb (the skipped-key
  cache removes the in-order-ratchet desync that forced fullres-only); `hydrateRow` decrypts both in order.
- **Signed-prekey rotation DONE** — `establishInbound` matches an incoming X3DH `spk` against the current
  OR `previousSignedPrekeys`, so a peer who fetched a now-rotated bundle still cold-starts. 1 round-trip spec.
  (Accepting a rotated prekey only; no periodic local-rotation job yet — flagged in the audit.)
- **Multi-device** documented as a v1 limitation (fan-out only; no cross-device sync / verify-other-device) —
  audit §5, not built (no-overengineering).
- **Crypto audit doc** — `plugins/meinchat-plus/docs/crypto-audit.md` (implementer self-review, explicitly
  NOT independent): primitives, X3DH+DR+hybrid-attachment construction, security properties, threat model,
  and **known limitations before public** — headline gap: **no identity-key verification UX (safety
  numbers / TOFU)**. README de-staled (dropped "in-order only" / "not yet wired").
- **Playwright e2e smoke** — `tests/e2e/prod-e2e.spec.ts` (env-gated, mirrors meinchat's `prod-chat.spec.ts`):
  manifest-enabled → device register → signed prekey → one-time prekeys → bundle fetch + **client-side
  signature verify** → conversation negotiates `e2e_v1`. Keys minted in-spec via `@noble/curves`.
- **Type-safety cleanup** — provider reworked to return the canonical meinchat `MessageRow`/`MessageAttachment`
  (was local `RowLike`) and accept a DRY-derived ISP `InboundRow` on the read path; **meinchat-plus now passes
  `vue-tsc` with zero errors** (project-wide tsc still red on pre-existing payment-plugin errors — out of scope).
- **Gates:** fe-user meinchat + meinchat-plus **156 vitest specs** GREEN, eslint clean, meinchat-plus tsc clean.

## S28 decisions locked 2026-05-28 (4 rounds, 16 questions)

| # | Question | Answer | Effect |
|---|---|---|---|
| R1-Q1 | Delivery-tracking granularity | **Join table** `meinchat_plus_message_delivery` | Matches spec — no doc change |
| R1-Q2 | Implementation order | **Ship 0+1+2 first** | Phase split into two master docs (R4-Q4) |
| R1-Q3 | iOS device-pairing UX | **Biometric primary + passphrase fallback** | s28-3b §4.2 + s28-7 §3.1 dual-mode KEK; web stays passphrase-only |
| R1-Q4 | Cross-device history recovery v1 | **Accept history loss on new device** | Matches spec — no doc change |
| R2-Q1 | s28-7 GA gate | **Enabled at v1 launch — no gating** | s28-7 framing rewritten — default-on at v1, opt-out via Settings |
| R2-Q2 | Envelope padding | **256-byte multiples** | Matches spec |
| R2-Q3 | Unpaired peer UX | **Strict 409 + UI hint** | Matches spec |
| R2-Q4 | vbwd.cc retention defaults | **2 days server / 10 days client** | Matches spec |
| R3-Q1 | External crypto audit | **Defer** — revisit when S28.3b implementation-ready | No doc change; revisit milestone |
| R3-Q2 | Pre-S28 plaintext history | **Auto-pruned at 2-day retention** | Covered by S28.1's plain-row prune |
| R3-Q3 | Group chats v1 | **1:1 only** | Matches spec |
| R3-Q4 | Push notifications v1 | **Out of scope; future plugin** | Matches spec §13 |
| R4-Q1 | New repo timing | **Public from day one** | s28-3b §2.0 open-source-posture section added |
| R4-Q2 | Operator break-glass key | **No — absolute E2E** | Matches spec's threat model |
| R4-Q3 | Web KEK derivation | **Argon2id via hash-wasm** | Matches spec's pick |
| R4-Q4 | Phase split into two master docs | **Yes** | s28-phase1 + s28-phase2 created; strategy doc points at both |

**Plus the receipt-UI requirement** (added 2026-05-28 alongside the
above): message bubbles render 0/1/2 small dots in the bottom-right
corner (WhatsApp-style) — 1 dot = delivered, 2 dots = read. Applies
to BOTH plain and e2e_v1 conversations (UI is protocol-agnostic via
new `message.delivered_at` + `message.read_at` columns added in
S28.3a). Spec lives in s28-6 §3.7 (iOS plain) + s28-7 §3.6 (iOS E2E,
reuses the same shared component) + a coordinated fe-user edit
under S28.2.

## Verification

- **Unit:** 2228 passed in `vbwd-backend` (+50 from S26+S27).
- **Integration:** 366 passed, 3 skipped.
- **Lint / mypy / black:** 0 errors.
- **End-to-end live:** open `@lololo` 100× → all 200 (S26); 7 × GET / with
  `RATELIMIT_DEFAULT_DAY=5` → 5 × 302 → 429 → 429 (S27, env honoured).

## Pending — needs user action

- **S28 open decisions.** The 2026-05-28 critical-review revision
  locked 11 of the earlier open questions; one remains:
  *server-side delivery telemetry granularity* — keep the
  `meinchat_plus_message_delivery` join table (recommended) or collapse
  to a single `delivered_device_count` column on `message`. See
  [s28#11](sprints/s28-meinchat-e2e-encryption-and-retention.md#11-open-decisions).
- **S29 — RESOLVED 2026-05-29.** Shipped §3.1 alone (route-meta flag); §3.2
  was already done by a CMS-guard refactor. **New open follow-up:** authed
  visitors at `/` are sent to the public CMS default slug by the CMS guard
  (no auth check) instead of `/dashboard`. Routing them to the dashboard
  needs a CMS-guard auth-skip — a small standalone follow-up sprint if that
  behaviour is wanted.
- **S31 keyfunc signature verification.** Before any implementation:
  the drafted `_rate_limit_key_func` skipped JWT signature verification.
  That opens a DoS vector (forge victim's user_id → fill their bucket
  → lock them out). Verify HS256 signature in the keyfunc; fall back
  to IP on signature failure.

## Other findings

- **Heavy-load workflow run #26452905684 failed by harness drift, not by the API.**
  Threshold guard tripped at 46.61 % error rate, but p95 = 12 ms across
  4 460 requests — the system is healthy; the harness is broken in two
  places (`populate_db.py` for 8 plugins ran outside the api container
  and silently failed; the Locust scenario drifted from the live API
  contract). Four mechanical fixes in
  [`reports/04-heavy-load-26452905684-harness-drift.md`](reports/04-heavy-load-26452905684-harness-drift.md).

## Blockers

- **None blocking S26 / S27.** Both shipped and verified.
- **S28 Phase 1** is **DONE & green** (S28.0/1/2, backend + web; iOS
  deferred). **Phase 2:** S28.3a ✅ + **S28.3b backend ✅ DONE & green**
  (meinchat-plus dormant). Next: the **meinchat-wiring slice** (send-path
  `expected_device_ids` + `envelope_b64`, scheduler `IRetentionPolicy`
  resolution, oracle updates) to unlock global-enable + the full round-trip,
  **then S28.4** (attachment encryption). 6/7 (iOS) in progress by the iOS
  agent. Phase-2 seams (`loadKek()`, `IRetentionPolicy`) are in place.
- **S29** is **DONE & green** (flash-fix only; see Work done 2026-05-29).
- **S30** is implementation-ready.
- **S31** is **blocked by the keyfunc signature-verification fix**
  (see Pending). Without that fix it actively regresses prod security
  — must not implement as currently drafted.
- **S32 / S33** are implementation-ready follow-ups.
- **S34** is **DEFERRED** by design — gated on S26 reaching every
  prod instance + one deploy cycle elapsing.
- **S35** is implementation-ready; ships on whatever iOS release
  follows.
