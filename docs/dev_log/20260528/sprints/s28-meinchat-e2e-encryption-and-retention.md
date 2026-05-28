# S28 — Meinchat extension seams + meinchat-plus (Signal ratchet) + retention windows

**Status:** PLANNED — 2026-05-28. Decided this turn:
- **Two-track delivery.** First refactor `meinchat` so it works alone *and*
  serves as a base for downstream plugins — extract narrow ports, default
  to identity/no-op behaviour so meinchat-alone behaviour is unchanged.
  Then ship `meinchat-plus` as a separate plugin that registers a
  Signal-ratchet `IBodyCodec` + `IDeviceDirectory` against those ports
  (Constellation A from the original alternatives list).
- **Defaults.** Server retention **2 days**; client retention **10 days**
  (suggested; client may **shorten only**, never extend beyond the
  server's suggestion).
- **Admin-configurable** per-instance via meinchat's plugin
  `config.json` + `admin-config.json`.
- **`GET /api/v1/messaging/limits`** endpoint surfaces the current values
  to the iOS app + web client + future native shells — zero hard-coded
  retention numbers on any client.
- **No `meinchat-enterprise` in this sprint.** Headroom is left in the
  port surface so it could be built later as a third plugin; not drafted
  here.

**Track:** sequential. Slice 3a (meinchat refactor) is the leverage; slice 3b
(meinchat-plus) depends on the ports landing first. Slices 0–2 stay in
meinchat and don't need any of that work.

**Repo touch:**
- `vbwd-backend` — `plugins/meinchat/` (refactor + new ports + new routes).
- `vbwd-fe-user/plugins/meinchat` (client cache, capabilities consumer).
- `vbwd-ios-plugin-meinchat` (client cache, capabilities consumer).
- **NEW:** `vbwd-plugin-meinchat-plus` (Signal ratchet on the backend).
- **NEW:** `vbwd-fe-user-plugin-meinchat-plus` (web crypto + device pairing).
- **NEW:** `vbwd-ios-plugin-meinchat-plus` (iOS crypto + device pairing).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID ·
DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING**
— [`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

**Gate:** `bin/pre-commit-check.sh --full` GREEN on every touched repo;
`bin/pre-commit-check.sh --plugin meinchat` and `--plugin meinchat-plus`
GREEN; the host apps + the iOS packages green on their respective CIs.

---

## 1. Goal (user value)

1. **Confidentiality.** With meinchat-plus enabled, chat bodies are
   readable only on the participants' currently-trusted devices. The
   operator, a DB snapshot, and an SSE eavesdropper all see ciphertext.
2. **Asymmetric retention.** The server holds at most **2 days** of
   message rows; every paired device holds up to **10 days** locally.
3. **Per-instance ops control.** Both windows + the ciphertext size
   cap are admin-configurable from the meinchat plugin admin UI — no
   redeploy.
4. **Plugin-ready core.** meinchat is robust standalone (plaintext +
   short-retention chat) **and** is the substrate for meinchat-plus
   (and any future extension) via narrow ports with null defaults.
5. **Native parity.** iOS and web fetch the current limits at runtime
   from `GET /api/v1/messaging/limits` instead of hard-coding anything.

---

## 2. Current state (proof of pain)

- `vbwd_backend.message.body TEXT, length ≤ 4000` — plaintext forever,
  no TTL.
- SSE pushes the same plaintext bodies that REST returns. TLS only.
- `useMeinchatStore.messagesByConv` — Pinia in-memory; full history
  refetched from the server on every reload.
- Attachments: plaintext bytes in `IFileStorage`; URL on
  `message.attachment_url` is also plaintext.
- `MessageService.send_text(...)` is monolithic — no extension seams.
- No concept of "device" in meinchat (it knows users + nicknames).

The system has zero E2E surface today and meinchat exposes zero
extension points for one.

---

## 3. Three alternative constellations (for the record)

The user picked **A** (Signal ratchet) as the chosen path for
`meinchat-plus`. B and C remain documented so the trade is auditable
later.

### Constellation A — Signal-style per-conversation ratchet — **CHOSEN**

- **Where it lives.** `meinchat-plus` plugin tree (backend + fe-user +
  iOS). meinchat alone never includes Signal.
- **Key model.** Each conversation has a symmetric session key advanced
  by a double-ratchet (DH + symmetric-key derivation) on every message.
  Forward secrecy + post-compromise security.
- **Library.** `libsignal-protocol` (Swift + JavaScript bindings;
  audited and maintained).
- **What the server sees.** Ciphertext + opaque header. Cannot add
  itself to the conversation. Cannot read messages even with full DB
  + Redis access.
- **Group chats.** N² key updates (or Sender Keys layer). Out of scope
  for this sprint — 1:1 only.
- **Pros.** Best end-state security; the protocol the industry has
  converged on.
- **Cons.** Most code; new dependency on libsignal; ratchet state
  needs persistence + reset semantics.
- **Why it's acceptable here.** It lives in a separate plugin — meinchat
  baseline stays light. The complexity is opt-in per instance.

### Constellation B — Per-device sealed-box envelope (libsodium) — alternative

- Each device publishes an X25519 public key; sender seals one envelope
  per recipient device using `crypto_box_seal`.
- No forward secrecy (single-device-key compromise lets an attacker
  read every envelope ever addressed to that device).
- Half the client code of A; smaller dependency.
- **Why not chosen:** the user picked A's forward-secrecy guarantee
  over B's simplicity.

### Constellation C — Server-side at-rest encryption with KMS — alternative

- Body encrypted before write; server holds the key.
- **Not E2E.** Operator can read.
- Listed for completeness so the trade is visible. **Not chosen.**

### Comparison matrix

| Property | A — Signal ratchet — **CHOSEN** | B — Per-device sealed-box | C — Server-side KMS |
|---|---|---|---|
| Operator can read | No | No | **Yes** |
| Forward secrecy | Yes | No (mitigated by retention only) | No |
| Post-compromise secrecy | Yes | No | No |
| Client complexity | High | Medium | None |
| Server complexity | Medium | Low | Low (with KMS) |
| Group-chat cost per message | N² (or Sender Keys layer) | N | 1 |
| Compatible with iOS / web / future Android | Yes (libsignal) | Yes (libsodium) | Yes |
| Plays well as a separate plugin layer | **Yes** — clean codec port substitution | Yes | Awkward (server holds key — couples with core) |

---

## 4. meinchat refactor — the six ports

meinchat becomes a *pipeline + registries* with **identity defaults** so
the standalone behaviour is byte-for-byte unchanged. Each port has a
default impl in meinchat itself; downstream plugins (meinchat-plus, and
any future extension) substitute or layer on.

### Port matrix

| Port | Arity | Default in meinchat | What meinchat-plus registers |
|---|---|---|---|
| `IMessageValidator` | **multi**, all-must-pass | length ≤ N + non-empty | "must be ciphertext when e2e in force for this conversation" |
| `IBodyCodec` | **single**, default = **identity** | passthrough (`encode(body)→body`) | **`SignalRatchetCodec`** (encrypt on send, decrypt on read) |
| `IMessagePersister` | **single**, default = DB row | write to `message` table | unchanged |
| `IBroadcaster` | **multi**, fan-out | `SseBroadcaster` only | unchanged |
| `IPostSendHook` | **multi**, **never fails the send** | none | `RotateRatchetState` (after-the-fact ratchet bookkeeping) |
| `IConversationFactory` | **single** | `start_or_get` (current behaviour) | unchanged |
| `IConversationPolicy` | **multi**, all-must-allow | block-list respected | "both participants must have ≥1 active device key" |
| `IConversationCapabilities` | **multi**, set-union | `{"plain"}` | adds `"e2e_v1"` |
| `IDeviceDirectory` | **single** | **null directory** (`lookup_active → []`; `register` raises `DirectoryNotEnabledError`) | real directory backed by `user_device_key` table owned by `meinchat-plus` |
| `IRetentionPolicy` | **single** | reads `messages_retention_days_server` / `attachments_retention_days_server` from config | unchanged (the policy is per-instance ops; not crypto's business) |
| `INotificationDispatcher` | **multi**, fan-out, error-tolerant | none (only SSE today; push lives in a future plugin) | unchanged |
| `IRateLimitPolicy` | (already exists, S26) | per-platform overrides | meinchat-plus may add a `device_registration` category |

### Resolver shape

Two shared helpers in `meinchat/extensibility/registry.py` so the same
pattern doesn't get reimplemented per port:

```python
def resolve_first(port_cls):    # single-impl ports (codec, persister, …)
    impls = registry.get(port_cls)
    return impls[-1] if impls else DEFAULTS[port_cls]  # last-write-wins

def resolve_all(port_cls):      # multi-impl ports (validators, broadcasters, …)
    return registry.get(port_cls) or []
```

`registry.get(...)` is a typed wrapper around the existing plugin
registry pattern (mirrors `paymentDataContributors` /
`checkoutPaymentMethods`).

---

## 5. Schema concessions in meinchat

Small, additive, **backward-compatible** — every existing plaintext row
keeps working with `protocol = 'plain'` and `envelope = NULL`.

| Table | Column | Type | Notes |
|---|---|---|---|
| `message` | `envelope` | `BYTEA NULL` | ciphertext + ratchet header when `protocol != 'plain'` |
| `message` | `protocol` | `VARCHAR(32) NOT NULL DEFAULT 'plain'` | discriminator |
| `conversation` | `protocol` | `VARCHAR(32) NOT NULL DEFAULT 'plain'` | the protocol negotiated at create-time |
| `conversation` | `capabilities` | `JSONB NOT NULL DEFAULT '[]'` | the negotiated capability set, surfaced to clients |

`message.body TEXT ≤ 4000` constraint preserved for plain rows
(`length(body) ≤ 4000 OR protocol != 'plain'`). Ciphertext is allowed
to exceed 4 000 because the libsignal preamble + payload base will not
fit otherwise.

The `user_device_key` table (and any meinchat-plus state) lives in
**`plugins/meinchat-plus/migrations/`** — not in meinchat. Follows the
existing "plugin migrations live in the plugin" convention.

---

## 6. Wire contract additions

Bounded surface, all read-only auth-gated GETs except where noted.

### `GET /api/v1/messaging/limits`

Returns current retention + size limits + enabled protocols.

```json
{
  "messages_retention_days_server": 2,
  "messages_retention_days_client_suggested": 10,
  "attachments_retention_days_server": 2,
  "ciphertext_max_bytes": 16384,
  "enabled_protocols": ["plain", "e2e_v1"]
}
```

`enabled_protocols` is the union of every registered
`IConversationCapabilities` contributor. With meinchat alone it's
`["plain"]`; with meinchat-plus enabled it's `["plain", "e2e_v1"]`.

### `GET /api/v1/messaging/capabilities`

Server-wide capability surface (same data, different framing — kept as
a separate endpoint so the client can read it before authenticating if
we ever want a public landing page).

### `GET /api/v1/messaging/me/capabilities`

Per-user capability surface. With meinchat-plus enabled but the user
having no device keys: `["plain"]`. After the user registers a key:
`["plain", "e2e_v1"]`.

### `POST /api/v1/messaging/conversations`

Extended to accept an optional `accepted_protocols: ["e2e_v1", "plain"]`
from the initiator. Server returns the negotiated `protocol` +
`capabilities` in the response. With meinchat alone the field is
ignored (server returns `"plain"`).

### Client retention enforcement (shorten-only)

iOS and web settings let the user set a local-retention value in
`[0, messages_retention_days_client_suggested]`. The UI greys out
anything above the server's suggestion. Enforced client-side; the
server has no opinion (it has no way to compel clients).

---

## 7. Sub-sprints (one file per slice; this doc is the strategy index)

Each sub-sprint is a self-contained TDD-first dev plan: files, specs,
acceptance, out-of-scope, engineering-requirements check.

| # | Sub-sprint | Lives in | Depends on | Backward compat? |
|---|---|---|---|---|
| 0 | [Config keys + `/limits` endpoint + iOS/web consumers](s28-0-config-and-limits-endpoint.md) | meinchat | none | Yes — surfaces values that are also the today-implicit defaults |
| 1 | [Server retention prune (daily APScheduler)](s28-1-server-retention-prune.md) | meinchat | S28.0 | Yes — at 2d the prune is a real change on prod; documented in deploy notes |
| 2 | [Client local cache with 10-day TTL + shorten-only UI](s28-2-client-local-cache.md) | meinchat (web + iOS) | S28.0 | Yes — purely additive |
| **3a** | [meinchat extension ports + schema concessions + capability endpoints (refactor)](s28-3a-meinchat-extension-ports.md) | meinchat | S28.0 | Yes — pure refactor + additive schema; "plugin-free still works" oracle proves byte-equal behaviour |
| **3b** | [`meinchat-plus` (Signal ratchet + device directory + prekey bundles)](s28-3b-meinchat-plus-signal-ratchet.md) | **new repos**: `vbwd-plugin-meinchat-plus` + `vbwd-fe-user-plugin-meinchat-plus` + `vbwd-ios-plugin-meinchat-plus` | S28.3a | n/a — new plugin, opt-in per instance |
| 4 | [Attachment encryption (mirror of S28.3 on the file path)](s28-4-attachment-encryption.md) | meinchat + meinchat-plus | S28.3a + S28.3b | Plain attachments keep working; e2e conversations write ciphertext blobs |

**Slices 0–2 ship inside meinchat and do not depend on the refactor.**
**Slice 3a is the leverage.** Once it lands, slice 3b is small (most of
the surface is in the three plugin repos) and a future
`meinchat-enterprise` would slot into the same ports without re-touching
meinchat.

---

## 8. meinchat-plus design (Constellation A)

### Server-side surface

- **Tables** (in `plugins/meinchat-plus/migrations/`):
  - `user_device_key (id, user_id FK vbwd_user, public_key BYTEA, algorithm, label, created_at, last_seen_at, revoked_at)`.
  - Optional `prekey_bundle` table for libsignal one-time prekeys
    (decision: include from day one — Signal needs it for async first
    messages).
- **Routes** (under `/api/v1/messaging/`):
  - `POST /me/devices` — publish a public key + prekey bundle.
  - `GET /users/{user_id}/devices` — list active devices of a peer.
    Rate-limited (`device_registration` category, registered with the
    existing `IRateLimitPolicy`).
  - `DELETE /me/devices/{id}` — revoke a device.
- **Codec** registered on enable:
  ```python
  pipeline.register(IBodyCodec, SignalRatchetCodec())
  pipeline.register(IDeviceDirectory, UserDeviceKeyDirectory(session))
  pipeline.register(IConversationCapabilities, lambda: {"e2e_v1"})
  pipeline.register(IConversationPolicy, BothPeersHaveDeviceKeys())
  ```
- **`PluginMetadata.dependencies = ["meinchat"]`** — the loader will
  refuse to enable meinchat-plus if meinchat is disabled, and refuse to
  disable meinchat while meinchat-plus is enabled. Validated in
  `vbwd/plugins/manager.py:114-118` + `:189-197`.

### Client-side (web + iOS)

- **Web (`vbwd-fe-user-plugin-meinchat-plus`):** `tweetnacl-js` plus the
  libsignal-protocol JS port. Private key in IndexedDB under WebCrypto
  non-exportable cred where available, else encrypted-at-rest LocalStorage.
- **iOS (`vbwd-ios-plugin-meinchat-plus`):** CryptoKit + the libsignal
  Swift package. Private key in Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (default; tighter
  `WhenUnlocked` available as a per-user setting if needed).
- **Pairing.** First app open after enabling meinchat-plus generates a
  fresh keypair and posts the public key to `POST /me/devices`. From
  that moment, messages addressed to this user route ciphertext
  envelopes (one per recipient device).

### What `meinchat-plus` explicitly does NOT do

- **Group chats** (Sender Keys layer is a separate sprint).
- **Recovery codes / cross-device history transfer.** New devices read
  only what the server has ciphertext for, addressed to their own
  brand-new key (i.e. **nothing** before pairing). The 10-day local
  cache on each paired device is the offline archive.
- **Tier gating via the subscription plugin.** Operator-enabled
  per-instance, no `subscription` dependency. (Can be added later as a
  separate slice if needed.)

---

## 9. Discipline that keeps meinchat usable alone

Three oracle tests in meinchat's CI:

1. **"Plugin-free still works."** With zero downstream plugins loaded,
   meinchat's full e2e suite passes — proves the null defaults are
   real, not vestigial. Asserted in `tests/e2e/test_meinchat_alone.py`
   (NEW for slice 3a).
2. **"Identity is identity."** Round-trip the default `IBodyCodec` on
   a random body and assert byte-equality. Catches anyone "improving"
   the default into something subtly different.
3. **"PostSendHooks never fail the send."** A throwing hook is caught,
   logged at error level, and the send still succeeds. Prevents a
   future audit-log plugin from breaking a user's chat.

Plus the existing rule from CLAUDE.md mirrored at this level:
**"meinchat never imports from a downstream plugin."** Enforced by a
static-analysis spec that greps `plugins/meinchat/` for any
`from plugins.meinchat_plus.*` / similar import statement.

---

## 10. Test plan (TDD-first)

Every slice opens with a red CHARACTERISATION test on existing
behaviour and closes with the green CONTRACT test on the new one.

Backend (`vbwd-backend`):
- `tests/unit/services/test_retention_service.py` — slice 1, ≥ 6 specs
  (boundaries: =N days, < N days, = 0 prunes all, days=∞ prunes
  nothing, idempotent re-run, attachment best-effort survives missing
  files).
- `tests/unit/routes/test_limits_endpoint.py` — slice 0, ≥ 5 specs
  (each field present, auth required, 404 when plugin disabled,
  reflects admin-changed config).
- `tests/unit/extensibility/test_pipeline_registry.py` — slice 3a, ≥
  10 specs (single-impl last-write-wins, multi-impl ordering,
  identity-codec round-trip, validator fan-fail, throwing post-hook
  isolated).
- `tests/integration/test_meinchat_alone.py` — slice 3a, oracle:
  spin up the app with **no plugins**, send/receive plain messages
  end-to-end, retention prune runs cleanly.
- `tests/integration/test_e2e_round_trip.py` — slice 3b (in
  `meinchat-plus` repo, not meinchat): two test users + one device
  each, message round-trip via the real route handler + DB; assert
  the server byte-stream never contains the plaintext body bytes.

Web (`vbwd-fe-user`):
- `plugins/meinchat/tests/unit/composables/use-local-message-cache.spec.ts`
  — slice 2, ≥ 4 specs (insert/read/evict at TTL, survives store
  recreation).
- `plugins/meinchat-plus/tests/unit/services/envelope.spec.ts` — slice
  3b, round-trip, tamper detection.

iOS:
- `MeinChatPluginTests/RetentionCacheTests.swift` — slice 2.
- `MeinChatPlusPluginTests/EnvelopeRoundTripTests.swift` — slice 3b.

---

## 11. Open decisions (still pending)

These need a vote before slice 0 lands.

1. **Strict fallback when a peer has no device key (slice 3b).**
   *Recommended: strict.* If meinchat-plus is enabled for the
   conversation and any recipient has no active device key, the send
   fails with a UI hint ("ask @bob to enable secure chat on a device").
   The alternative (mixed mode — silently fall back to plaintext) leaks
   under the operator-blind goal.
2. **iOS device-key storage class.** *Recommended:
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.* `WhenUnlocked`
   is tighter (key unreadable while phone is locked) but breaks
   background-fetch decryption.
3. **Pipeline-port arity matrix** as per §4 — multi-validator,
   single-codec, single-persister, multi-broadcaster, multi-posthook.
   *Recommended: as proposed.* Particular concern: do you want
   chain-of-responsibility codecs (e.g. compress then encrypt) instead
   of single? My vote is single — keeps decryption deterministic and
   the protocol field unambiguous.
4. **Schema discriminator** — keep `body TEXT` (plain only) + sibling
   `envelope BYTEA` for ciphertext, with `protocol` discriminator on
   `message` + `conversation`. *Recommended: as proposed.* The
   alternative — single `body BYTEA` with discriminator only — is more
   minimal but loses pgAdmin readability for plain rows and forces
   client base64 handling everywhere.
5. **iOS `WhenUnlocked` vs `AfterFirstUnlockThisDeviceOnly` (per-user
   toggle).** Should there be a settings switch, or is the
   `AfterFirstUnlockThisDeviceOnly` default enough? *Recommended:
   default-only for slice 3b; surface a toggle later if anyone asks.*
6. **`prekey_bundle` table at slice 3b or later?** *Recommended: at
   slice 3b.* Signal needs prekeys for async first-message delivery
   (sender encrypts to a recipient whose device is offline). Without
   them, two users must be online simultaneously to bootstrap a
   conversation. Including is a small extra migration; deferring is a
   real UX regression.

---

## 12. Engineering-requirements check (BINDING)

- **TDD-first.** Every slice opens with red characterisation on
  today's behaviour, closes with green contract on the new one. The
  refactor slice 3a in particular: characterisation test asserts
  meinchat-alone behaviour is byte-for-byte unchanged.
- **DevOps-first.** Schema changes via Alembic only. Each slice ships
  in CI green from a cold start. Retention prune + limits endpoint
  validate end-to-end in the integration suite.
- **SOLID.**
  - *S* — each port has one job (codec encodes, persister persists);
    no fat ports.
  - *O* — every new behaviour comes from a registered impl, never an
    `if plugin_name == "meinchat-plus"` branch in meinchat.
  - *L* — the null-default impls are behaviour-preserving substitutes
    of the real ones (identity codec round-trips, null directory
    answers `[]` consistently, …).
  - *I* — ports are narrow (e.g. `IDeviceDirectory` has 4 methods, not
    every CRUD operation on devices).
  - *D* — meinchat depends only on its own ports + container; never
    imports from `meinchat-plus`. Static-analysis spec asserts this.
- **DI.** Resolvers go through `extensibility.registry.resolve_first` /
  `resolve_all`. Container provides session, clock, config-store; no
  module-level singletons in meinchat-plus state.
- **DRY.** A single `resolve_first` / `resolve_all` helper backs every
  port; one `RetentionService` answers "should this row be pruned?"
  for both the cron job and the dual-protocol read path.
- **Liskov.** Both server and clients tolerate envelopes from any
  algorithm version (`protocol` field carries the version); bumping
  it later doesn't break the wire contract.
- **Clean code.** No magic numbers — every retention window is a
  named config key. Ports stay narrow (4 methods or fewer each).
- **NO OVERENGINEERING.** Only the ports needed to support
  meinchat-plus are extracted in slice 3a. `meinchat-enterprise` is
  *not* drafted; the port surface is general enough that it could be
  built later, no speculative interfaces added now.
- **Core agnostic.** No core changes in `vbwd-backend/vbwd/`. All
  work lives in `plugins/meinchat/` + `plugins/meinchat-plus/` +
  client plugin trees.
- **Quality gate.** `bin/pre-commit-check.sh --full` GREEN on
  `vbwd-backend`; `--plugin meinchat` GREEN; `--plugin meinchat-plus`
  GREEN; the host apps + iOS package green on their respective CIs.

---

## 13. Out-of-scope follow-ups

Documented so they don't sneak back into S28:

- **Group chats** — Sender Keys layer on top of meinchat-plus. New
  sprint when needed.
- **Recovery codes / cross-device history transfer.** Optional UX
  improvement; the 10-day per-device local cache covers the primary
  reading surface. New sprint when asked.
- **Push notifications (APNS/FCM).** A future
  `meinchat-push` plugin would register an `INotificationDispatcher`.
  Out of scope for S28.
- **Webhook outbound for chat events.** Same pattern — new plugin.
- **`meinchat-enterprise`.** Not drafted in this sprint per user
  decision. The port surface is general enough to host it later
  (validators for DLP, persister for archive mirror, broadcasters for
  webhooks, etc.) without re-touching meinchat.
- **Tier-gating meinchat-plus via the subscription plugin.** Today
  it's operator-enabled per-instance. Adding entitlement-gated
  enablement is a small follow-up if/when needed.

---

## Anchor

Inherits the binding engineering requirements at
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md)
and extraction rules at
[`../../20260519/sprints/_engineering-requirements.md`](../../20260519/sprints/_engineering-requirements.md).
