# 2026-05-28 — Daily status

> **Resume tomorrow from [`handoff-s28.md`](handoff-s28.md)** (S28 E2E track).
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
| 28 | [Meinchat extension seams + meinchat-plus (Signal ratchet) + retention (10d clients / 2d server)](sprints/s28-meinchat-e2e-encryption-and-retention.md) — strategy index, split into **[Phase 1](sprints/s28-phase1-retention-and-config.md)** (retention + config + cache) + **[Phase 2](sprints/s28-phase2-e2e-and-ios.md)** (E2E + iOS) | meinchat (`vbwd-backend`/`plugins/meinchat`, `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`) **+ new** `meinchat-plus` (3 new plugin repos, **public from day one**) **+ iOS app update + iOS meinchat-plus plugin (enabled at v1 launch)** | **Phase 1 DONE — IMPLEMENTED & GREEN 2026-05-29** (backend + web; iOS deferred): [S28.0](done/s28-0-config-and-limits-endpoint.md) · [S28.1](done/s28-1-server-retention-prune.md) · [S28.2](done/s28-2-client-local-cache.md) ([report 05](reports/05-s28-phase1-and-s29-implementation.md)). **Phase 2 IN PROGRESS:** [S28.3a](done/s28-3a-meinchat-extension-ports.md) ✅ DONE & GREEN 2026-05-29 (backend: ports/registry + e2e schema + capabilities + negotiation; 241 specs). 3b (meinchat-plus, new plugin) STARTED 2026-05-29 — server `SignalEnvelopeValidator` (holds no keys) + scaffold + config + cbor2 dep, 9 specs green; remaining: models/migration/repos/prekey services (FOR UPDATE SKIP LOCKED)/routes/round-trip. Then 4 (attachment enc), 6/7 (iOS, in progress by iOS agent) |
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
    - [S28.3b](sprints/s28-3b-meinchat-plus-signal-ratchet.md) — `meinchat-plus` (**client-encrypts** Signal ratchet + split `signed_prekey` / `one_time_prekey` tables + `FOR UPDATE SKIP LOCKED` consume + 256B padding + downgrade fail-closed + delivery tracking), 3 new plugin repos.
    - [S28.4](sprints/s28-4-attachment-encryption.md) — attachment encryption (client encrypts; new `meinchat_attachment` child table with `kind` enum for fullres + thumb dual blobs).
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
  deferred). **Phase 2** (3a/3b/4/6/7 + iOS) remains design-only and is
  gated on Phase 1 baking in prod for one deploy cycle (+ the §11 decision +
  iOS gating). Phase-2 seams (`loadKek()`, `IRetentionPolicy`) are in place.
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
