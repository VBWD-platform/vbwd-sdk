# S28 — Meinchat extension seams + meinchat-plus (Signal ratchet) + retention windows

**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb a critical
review that found:
- A server-side encryption design that broke the E2E claim (codec ran on the
  server, plaintext visible mid-encryption) → **client now encrypts, server
  validates + forwards**.
- An overclaim *"operator sees only ciphertext"* → re-stated honestly as
  *"operator cannot read message bodies"* with an explicit "what the
  operator still sees" subsection.
- 12 speculative ports → **6 concrete ports** with a named consumer for each
  (NO OVERENGINEERING).
- Three overlapping capability endpoints → **one** (`/messaging/capabilities`
  with an optional `me=true` query) (DRY).
- A protocol-downgrade attack vector → **client fail-closed** on negotiation;
  conversation `protocol` is pinned per-row.
- Retention prune deleting undelivered ciphertext → prune predicate now
  exempts E2E rows whose `delivered_to_all_addressed_devices_at` is null.
- Prekey-bundle race that could repeat the initial chain key → locked to
  `SELECT … FOR UPDATE SKIP LOCKED` with `consumed_at` set in the same txn.
- Sender unable to read own messages on a second device → recipient set
  now includes the sender's own active devices.
- Ciphertext length leaking plaintext length → mandatory padding to 256 B
  multiple before encryption.
- `body NOT NULL` blocking ciphertext rows → migration adds
  `ALTER COLUMN body DROP NOT NULL`.
- Cache contradiction (S28.2 holds decrypted bodies / no plaintext at rest)
  → cache stores plaintext **at rest under a wrapped key** (WebCrypto on
  web, Keychain on iOS), reconciled.

**Phase split (S28 decision R4-Q4 + R2-Q2 — 2026-05-28):** this doc
remains the **strategy / threat-model / locked-decisions index** for
the whole S28 family. Implementation lives in two phase masters:
- **[s28-phase1-retention-and-config.md](s28-phase1-retention-and-config.md)** —
  retention + config + cache (S28.0/1/2). Ships first, independent of
  crypto. Lifts the operator-amnesia privacy risk even if phase 2
  never lands.
- **[s28-phase2-e2e-and-ios.md](s28-phase2-e2e-and-ios.md)** — the
  meinchat-plus E2E track + the iOS app updates (S28.3a/3b/4/6/7).
  Ships after phase 1 has been in prod for one deploy cycle.

This strategy doc owns the threat model, the §11 locked decisions,
and the 16 Q&A decision log (linked from `status.md`); each phase
master inherits without copy-paste (DRY).

**Decided this turn:**
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

1. **Body confidentiality.** With meinchat-plus enabled, chat **bodies**
   are readable only on the participants' currently-trusted devices.
   Encryption happens **client-side**; the server stores opaque
   ciphertext envelopes. The operator and a DB snapshot cannot read
   bodies. (An SSE eavesdropper sees ciphertext too — the SSE event
   carries only the `envelope` column, never plaintext.)
2. **Asymmetric retention.** The server holds at most **2 days** of
   delivered message rows; every paired device holds up to **10 days**
   locally (at-rest encrypted on disk under a wrapped key). Undelivered
   E2E rows are exempt from the prune until every addressed device has
   fetched them (so async-first-message delivery via prekey bundles
   doesn't lose data — see §6 and S28.1).
3. **Per-instance ops control.** Both windows + the ciphertext size
   cap are admin-configurable from the meinchat plugin admin UI — no
   redeploy.
4. **Plugin-ready core.** meinchat is robust standalone (plaintext +
   short-retention chat) **and** is the substrate for meinchat-plus
   (and any future extension) via the **six** narrow ports listed in
   §4 — each has a concrete consumer in S28.3b. No speculative ports.
5. **Native parity.** iOS and web fetch the current limits at runtime
   from `GET /api/v1/messaging/limits` instead of hard-coding anything.
6. **Honest threat model.** What the operator can **still** observe even
   with meinchat-plus enabled:
   - Identity of conversation participants (`vbwd_user` rows + the
     `participant_low_id`/`participant_high_id` FKs on `conversation`).
   - Message *timing* (the `sent_at` column).
   - Approximate message length (after the §6 padding rounds it to a
     256-byte multiple — see "padding" in §8).
   - Per-user device fingerprints (each device registers a public key
     visible to other authenticated users via
     `GET /messaging/users/<id>/devices`).
   - Per-user rate-limit telemetry (the S33 429 log lines).
   Anything stronger (metadata privacy, anonymous routing) is **out of
   scope** for S28 — call it out instead of overclaiming.

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

## 4. meinchat refactor — the six concrete ports

meinchat becomes a *pipeline + registries* with **identity / null
defaults** so the standalone behaviour is byte-for-byte unchanged. Every
port listed has a **named concrete consumer in S28.3b**; nothing
speculative.

### Port matrix (NO OVERENGINEERING — only ports with a real consumer)

| Port | Arity | Default in meinchat | Concrete consumer (S28.3b unless noted) |
|---|---|---|---|
| `IBodyCodec` | **single**, default = **identity** | passthrough (`encode(body)→body`); decode is identity | **`SignalEnvelopeValidator`** — server-side, *no keys*: validates `protocol == "e2e_v1"`, envelope size ≤ `ciphertext_max_bytes`, fan-out is well-formed. (The actual encryption is **client-side**; see §8 §"Client encrypts, server forwards".) |
| `IConversationPolicy` | **multi**, all-must-allow | block-list respected | `BothPeersHaveDeviceKeys` — veto a `e2e_v1` start if any participant lacks an active device key |
| `IConversationCapabilities` | **multi**, set-union | `{"plain"}` | adds `"e2e_v1"` |
| `IDeviceDirectory` | **single** | **null directory** (`lookup_active → []`; `register` raises `DirectoryNotEnabledError`) | `UserDeviceKeyDirectory` backed by `meinchat_plus_user_device_key` |
| `IPostSendHook` | **multi**, **never fails the send** | none | `MarkDeliveryAttempted` — tracks per-device fetch progress so S28.1 can prune delivered E2E rows safely |
| `IRetentionPolicy` | **single** | reads `messages_retention_days_server` / `attachments_retention_days_server` from config | `E2eAwareRetentionPolicy` — exempts undelivered E2E rows from the prune (S28.1) |

### Ports we explicitly did NOT extract (overengineering check)

The earlier draft listed 12 ports. Six were dropped in this revision —
each had no concrete S28.3b consumer:

- **`IMessageValidator`** — only the default (length + non-empty)
  existed. Stays inline in `MessageService`; no port. Add the port only
  when a second validator with a real use case appears.
- **`IMessagePersister`** — only one consumer (the SQLAlchemy repo).
  Stays inline; the message-row write is not a meaningful seam.
- **`IBroadcaster`** — only one consumer (`SseBroadcaster`). The "future
  push plugin" justification is speculative — defer until that plugin
  is in flight.
- **`IConversationFactory`** — `start_or_get` has no replacement on the
  horizon; the row creation logic is not a meaningful seam.
- **`INotificationDispatcher`** — speculative (push notifications are
  a separate plugin idea, not in this slice's port surface).
- **`IRateLimitPolicy`** — already exists from S26 inside meinchat; no
  need to re-introduce a port name for it here.

If a real second consumer for any of these appears, **add the port then,
not now**. (DRY corollary: today's behaviour stays as a single concrete
method, no abstraction.)

### Resolver shape (DRY — one helper pair backs every port)

Two shared helpers in `meinchat/extensibility/registry.py`:

```python
def resolve_first(port_cls):    # single-impl ports (codec, device dir, retention)
    impls = registry.get(port_cls)
    return impls[-1] if impls else DEFAULTS[port_cls]  # last-write-wins

def resolve_all(port_cls):      # multi-impl ports (policy, capabilities, post-send)
    return registry.get(port_cls) or []
```

`registry.get(...)` is a typed wrapper around the existing plugin
registry pattern (mirrors `paymentDataContributors` /
`checkoutPaymentMethods`).

---

## 5. Schema concessions in meinchat

Small, additive, **backward-compatible** — every existing plaintext row
keeps working with `protocol = 'plain'`, `envelope = NULL`, and `body`
populated as today.

| Table | Column | Type | Notes |
|---|---|---|---|
| `message` | `envelope` | `BYTEA NULL` | client-encrypted ciphertext blob + per-recipient header when `protocol != 'plain'`. **Server never decrypts.** |
| `message` | `protocol` | `VARCHAR(32) NOT NULL DEFAULT 'plain'` | discriminator |
| `message` | `delivered_to_all_addressed_devices_at` | `TIMESTAMPTZ NULL` | set by `MarkDeliveryAttempted` (S28.3b `IPostSendHook`) once every recipient device has fetched. Read by `E2eAwareRetentionPolicy` (S28.1) to exempt undelivered async-first-message rows from the prune. NULL for plain rows (they're delivered as soon as they're written). |
| `conversation` | `protocol` | `VARCHAR(32) NOT NULL DEFAULT 'plain'` | the protocol negotiated at create-time; **immutable** after that (downgrade defence) |
| `conversation` | `capabilities` | `JSONB NOT NULL DEFAULT '[]'` | the negotiated capability set, surfaced to clients |

**`body NOT NULL` drops to nullable.** Ciphertext rows have `body IS
NULL`; plain rows continue to carry `body TEXT`. Migration:

```sql
ALTER TABLE message ALTER COLUMN body DROP NOT NULL;
ALTER TABLE message DROP CONSTRAINT IF EXISTS ck_message_body_len;
ALTER TABLE message ADD CONSTRAINT ck_message_body_len
    CHECK (protocol != 'plain' OR (body IS NOT NULL AND length(body) <= 4000));
ALTER TABLE message ADD CONSTRAINT ck_message_body_or_envelope
    CHECK ((protocol = 'plain' AND body IS NOT NULL AND envelope IS NULL)
        OR (protocol != 'plain' AND body IS NULL AND envelope IS NOT NULL));
```

Ciphertext envelopes are allowed to exceed 4 000 bytes (libsignal
preamble + per-recipient fan-out + padding); the size is bounded by the
admin-configurable `ciphertext_max_bytes` (default 16 384) and validated
server-side by `SignalEnvelopeValidator` (S28.3b §2.4).

The `meinchat_plus_user_device_key`, `meinchat_plus_signed_prekey`, and
`meinchat_plus_one_time_prekey` tables live in
**`plugins/meinchat-plus/migrations/`** — not in meinchat. Follows the
existing "plugin migrations live in the plugin" convention.

---

## 6. Wire contract additions

Bounded surface, all read-only auth-gated GETs except where noted. **DRY:
one `/capabilities` endpoint** carries both the server-wide set and the
caller-specific subset — the earlier draft had three overlapping
endpoints (`/limits`, `/capabilities`, `/me/capabilities`), reduced to
two here.

### `GET /api/v1/messaging/limits`

Operator-tunable knobs — retention windows + envelope size cap. Stable
even when no plugins are loaded.

```json
{
  "messages_retention_days_server": 2,
  "messages_retention_days_client_suggested": 10,
  "attachments_retention_days_server": 2,
  "ciphertext_max_bytes": 16384
}
```

### `GET /api/v1/messaging/capabilities[?me=true]`

Capability surface. Default (no `me` query) returns the union of every
registered `IConversationCapabilities.for_conversation(None)` — the
server-wide set:

```json
{ "server": ["plain", "e2e_v1"] }
```

With `?me=true` the server intersects with the caller's actual
usability (e.g. needs ≥ 1 active device key for `e2e_v1`):

```json
{ "server": ["plain", "e2e_v1"], "me": ["plain"] }
```

(One endpoint, two shapes by query param. The previous separate
`/me/capabilities` route is gone — the caller's auth already
identifies them.)

### `POST /api/v1/messaging/conversations` (extended)

Accepts an optional `accepted_protocols: ["e2e_v1", "plain"]` from the
initiator. Server intersects with peer's capabilities and pins the
result on `conversation.protocol`.

Response:

```json
{
  "id": "<uuid>",
  "protocol": "e2e_v1",
  "capabilities": ["plain", "e2e_v1"]
}
```

**Downgrade defence (client-side, mandatory for meinchat-plus clients):**
when the meinchat-plus client sends `accepted_protocols: ["e2e_v1"]`
(refuses plaintext fallback), it MUST fail-closed on any response with
`protocol != "e2e_v1"`. The client SHOULD warn the user that the
operator returned a weaker protocol than requested. Once a conversation
is pinned `e2e_v1`, the schema prevents it from being downgraded
(`conversation.protocol` is immutable; per-row check in S28.3b).

**Negotiation-failure error contract** (covers C6 of the critical
review):

| Cause | HTTP | `code` | `hint` |
|---|---|---|---|
| peer has no active device key, initiator demands e2e_v1 | 409 | `peer_has_no_device_keys` | `Ask @<peer> to enable secure chat on a device.` |
| `accepted_protocols ∩ peer_capabilities = ∅` | 409 | `protocol_negotiation_empty` | `No protocol accepted by both parties.` |
| `accepted_protocols` not a subset of server's enabled protocols | 400 | `protocol_not_enabled` | `Protocol <p> is not enabled on this instance.` |
| `accepted_protocols` missing or empty when omitted from a v2 client | 200 fallback | n/a | server returns `protocol: "plain"` (back-compat) |

### Client retention enforcement (shorten-only — best-effort)

iOS and web settings let the user set a local-retention value in
`[0, messages_retention_days_client_suggested]`. The UI greys out
anything above the server's suggestion. **This is enforced client-side
only — a forked or hostile client can ignore the cap.** Honest
restatement: "the operator publishes a suggested retention; well-behaved
clients respect it." Not a security guarantee.

---

## 7. Sub-sprints (one file per slice; this doc is the strategy index)

Each sub-sprint is a self-contained TDD-first dev plan: files, specs,
acceptance, out-of-scope, engineering-requirements check.

| # | Sub-sprint | Lives in | Depends on | Backward compat? |
|---|---|---|---|---|
| 0 | [Config keys + `/limits` endpoint + iOS/web consumers](../done/s28-0-config-and-limits-endpoint.md) | meinchat | none | Yes — surfaces values that are also the today-implicit defaults |
| 1 | [Server retention prune (daily APScheduler)](../done/s28-1-server-retention-prune.md) | meinchat | S28.0 | Yes — at 2d the prune is a real change on prod; documented in deploy notes |
| 2 | [Client local cache with 10-day TTL + shorten-only UI](../done/s28-2-client-local-cache.md) | meinchat (web + iOS) | S28.0 | Yes — purely additive |
| **3a** | [meinchat extension ports + schema concessions + capability endpoints (refactor)](s28-3a-meinchat-extension-ports.md) | meinchat | S28.0 | Yes — pure refactor + additive schema; "plugin-free still works" oracle proves byte-equal behaviour |
| **3b** | [`meinchat-plus` (Signal ratchet + device directory + prekey bundles)](s28-3b-meinchat-plus-signal-ratchet.md) | **new repos**: `vbwd-plugin-meinchat-plus` + `vbwd-fe-user-plugin-meinchat-plus` + `vbwd-ios-plugin-meinchat-plus` | S28.3a | n/a — new plugin, opt-in per instance |
| 4 | [Attachment encryption (mirror of S28.3 on the file path)](s28-4-attachment-encryption.md) | meinchat + meinchat-plus | S28.3a + S28.3b | Plain attachments keep working; e2e conversations write ciphertext blobs |

**Slices 0–2 ship inside meinchat and do not depend on the refactor.**
**Slice 3a is the leverage.** Once it lands, slice 3b is small (most of
the surface is in the three plugin repos) and a future
`meinchat-enterprise` would slot into the same ports without re-touching
meinchat.

---

## 8. meinchat-plus design (Constellation A) — **client encrypts, server forwards**

### Architecture in one sentence

The **client** runs libsignal-protocol, encrypts the body once per
recipient device, packs the resulting envelopes into one blob, and
POSTs it as `envelope` on `POST /messages`. The **server** validates
shape + size, stores the blob, broadcasts it, and tracks delivery.
**The server never sees plaintext** — it has no Signal session store, no
encryption code, no decryption code.

(This corrects the earlier draft's `SignalRatchetCodec.encode(self,
ctx)` that ran on the server and saw plaintext mid-encryption. That
draft was not E2E. Fixed in this revision.)

### Server-side surface (small — by design)

- **Tables** (in `plugins/meinchat-plus/migrations/`, see S28.3b §2.3
  for the full DDL):
  - `meinchat_plus_user_device_key (id, user_id FK vbwd_user, public_key BYTEA, algorithm, label, created_at, last_seen_at, revoked_at)`.
  - `meinchat_plus_signed_prekey (id, device_id FK, signed_prekey BYTEA, signature BYTEA, created_at, rotated_at)` — long-lived per device, periodically rotated by the client.
  - `meinchat_plus_one_time_prekey (id, device_id FK, prekey BYTEA, consumed_at)` — single-use, consumed via `SELECT … FOR UPDATE SKIP LOCKED` to prevent the race documented in the critical review.
  - `meinchat_plus_message_delivery (message_id FK, device_id FK, fetched_at)` — one row per (message, addressed device); `MarkDeliveryAttempted` writes here; the prune predicate reads here.
- **Routes** (under `/api/v1/messaging/`):
  - `POST /me/devices` — publish a public key + label. Server stores;
    does NOT generate keys. Rate-limited (`device_registration`, default `5/h`).
  - `GET /users/{user_id}/devices` — list active devices (+ public keys)
    of a peer so the **client** can fan out envelopes.
    Rate-limited (`device_lookup`, default `60/h`).
  - `DELETE /me/devices/{id}` — revoke; sets `revoked_at`. Idempotent.
  - `POST /me/prekeys/signed` — upload / rotate the device's signed prekey.
  - `POST /me/prekeys/one-time` — upload N (default 100) one-time prekeys.
  - `GET /devices/{device_id}/prekey-bundle` — atomic consume of one one-time prekey under `FOR UPDATE SKIP LOCKED`. Returns the signed prekey + one consumed one-time prekey. Refill signalled to the client via a `low-water-mark` header when count drops below 20.
- **Server-side codec is a validator** (NOT an encryptor):
  ```python
  class SignalEnvelopeValidator(IBodyCodec):
      """Server-side `IBodyCodec`. No keys; validates the envelope is
      well-formed and within size limits. Encryption happens on the
      client; we are a dumb forwarder of opaque bytes."""
      def encode(self, ctx: SendContext) -> EncodedBody:
          # ctx.body_or_envelope is ALREADY ciphertext (client encrypted).
          # Validate shape: protocol marker, fan-out header, size cap.
          envelope = ctx.body_or_envelope
          if not isinstance(envelope, bytes):
              raise InvalidEnvelopeError("envelope must be bytes")
          if len(envelope) > self._max_size:
              raise EnvelopeTooLargeError(...)
          header = parse_pack_header(envelope)  # raises on malformed
          # Optional: assert every device_id in the header is in the
          # recipient set the conversation knows about. (Defense in depth
          # against a misbehaving client.)
          for blob in header.per_recipient:
              if blob.device_id not in ctx.expected_device_ids:
                  raise UnknownRecipientDeviceError(blob.device_id)
          return EncodedBody(body=None, envelope=envelope, protocol="e2e_v1")

      def decode(self, row: Message, viewer_device: Device | None) -> str:
          # Server never decodes. The route handler returns the raw envelope
          # to the client; the client picks the blob addressed to its own
          # device and decrypts locally.
          raise NotImplementedError("decode is client-side only")
  ```
- **Registrations** on enable (one place; idempotent):
  ```python
  register(IBodyCodec, SignalEnvelopeValidator(max_size=cfg.ciphertext_max_bytes))
  register(IDeviceDirectory, UserDeviceKeyDirectory(session))
  register(IConversationCapabilities, E2eV1Capability())
  register(IConversationPolicy, BothPeersHaveDeviceKeys())
  register(IPostSendHook, MarkDeliveryAttempted(delivery_repo))
  register(IRetentionPolicy, E2eAwareRetentionPolicy(delivery_repo, cfg))
  ```
- **`PluginMetadata.dependencies = ["meinchat"]`** — the loader will
  refuse to enable meinchat-plus if meinchat is disabled, and refuse to
  disable meinchat while meinchat-plus is enabled. Validated in
  `vbwd/plugins/manager.py:114-118` + `:189-197`.

### Wire format for the `envelope` blob

The envelope is a length-prefixed CBOR (`cbor2` on the server, `cbor-x`
on the client; both audited, ~5 KB):

```cbor
{
  "v": 1,                                          # protocol version
  "per_recipient": [
    {
      "device_id": <uuid-bytes>,                   # which device this slot is for
      "ciphertext": <bytes>,                       # libsignal output
      "header": <bytes>                            # libsignal session header
    },
    ...
  ]
}
```

**Padding (closes the length-leak hole from the critical review):**
before the libsignal encrypt call on the client, the plaintext body is
padded with random bytes to the next 256-byte multiple. The padding
length is encoded in the first 2 bytes of the padded plaintext (so the
recipient can strip it after decrypt). All envelopes for the same
message thus carry equal ciphertext length, and an observer learns
plaintext length only to ±256 bytes.

### Client-side (web + iOS) — the actual crypto

- **Web (`vbwd-fe-user-plugin-meinchat-plus`):**
  `@signalapp/libsignal-client` JS bindings; pad → encrypt → fan out
  client-side. Device private key in IndexedDB **wrapped under a
  passphrase-derived KEK** (Argon2id 64 MB memory, 3 iters; fallback to
  PBKDF2 600k iters where Argon2id isn't available). Locked decision —
  WebCrypto `extractable=false` is incompatible with libsignal-JS's
  raw-key API (critical review §C17).
- **iOS (`vbwd-ios-plugin-meinchat-plus`):** CryptoKit + the libsignal
  Swift package. Device private key in Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (locked default).
  No per-user toggle to `WhenUnlocked` in this slice — background tasks
  (S28.2 cache prune, S28.3b refill-prekeys) need access while locked.
- **Pairing.** First app open after enabling meinchat-plus generates a
  fresh keypair, posts the public key to `POST /me/devices`, then uploads
  N one-time prekeys + the signed prekey. From that moment, messages
  addressed to this user can be E2E-routed.
- **Sender fans out client-side.** The sending client calls
  `GET /messaging/users/<peer>/devices` (which returns the peer's active
  device ids + public keys) **plus** `GET /messaging/users/<self>/devices`
  (so the sender's other devices can also decrypt — closes critical
  review §C7). It encrypts to each, packs the envelopes, POSTs the blob.
  Single recipient pair count today; trivially extends to multi-device.

### Delivery tracking — closes the "prune deletes undelivered" hole

`MarkDeliveryAttempted` is an `IPostSendHook` that, on each
authenticated `GET /messages/<conv_id>?since=…` from a device, inserts a
`meinchat_plus_message_delivery (message_id, device_id, fetched_at)` row
for every message the response includes (no-op if already present —
idempotent under unique key). When the count of rows with
`fetched_at IS NOT NULL` equals the count of devices the envelope
addressed, the row's `delivered_to_all_addressed_devices_at` is set to
`now()`. S28.1's `E2eAwareRetentionPolicy` exempts rows where that
column is NULL.

### What `meinchat-plus` explicitly does NOT do

- **Group chats** (Sender Keys layer is a separate sprint).
- **Recovery codes / cross-device history transfer.** New devices read
  only ciphertext addressed to their own brand-new key (i.e. **nothing**
  before pairing). The 10-day local cache on each paired device is the
  offline archive.
- **Tier gating via the subscription plugin.** Operator-enabled
  per-instance, no `subscription` dependency.
- **Server-side ratchet state.** Lives on the client. The server's
  `signed_prekey` + `one_time_prekey` tables hold only the *public*
  half — no session state.
- **Metadata privacy.** Conversation participants, timing, and
  approximate message length remain visible to the operator (§1.6).

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

## 11. Open decisions

The critical review locked most of these in this revision. Only one
genuine open question remains.

### Locked in this revision (no vote needed)

1. **Strict fallback when a peer has no device key.** **Strict.** Mixed
   mode silently downgrades and leaks under the operator-blind goal.
2. **iOS device-key storage class.**
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No per-user
   toggle in this slice (background tasks need access while locked).
3. **Pipeline-port arity matrix.** Reduced to **six concrete ports**
   (§4). Six speculative ports dropped per NO OVERENGINEERING.
4. **Schema discriminator.** `protocol` on both `message` and
   `conversation`; `body` becomes nullable; CHECK constraints enforce
   the body-XOR-envelope invariant per protocol.
5. **`prekey_bundle` table at slice 3b.** Yes — split into
   `signed_prekey` + `one_time_prekey` (per Signal spec, NOT one merged
   table — the conflated draft was a DRY violation that masked the
   different rotation lifecycles).
6. **Server-side vs client-side encryption.** **Client-side.** The
   earlier server-side draft was not E2E.
7. **Padding.** Plaintext padded to next 256-byte multiple before
   encryption.
8. **Prekey consumption race.** `SELECT … FOR UPDATE SKIP LOCKED` +
   `consumed_at = now()` in the same txn. Locked — `advisory_lock` left
   as an option in the earlier draft was a NO-OVERENGINEERING-violating
   spec gap.
9. **Downgrade defence.** Client fail-closed when `accepted_protocols =
   ["e2e_v1"]` and response `protocol != "e2e_v1"`. Conversation
   `protocol` is immutable on the row (schema-pinned).
10. **Sender's own devices in recipient list.** Yes — client fans out
    to peer's devices AND own active devices. Lets the sender read
    their own messages on a second device.
11. **Cache at-rest encryption.** Yes (S28.2 §2.1/§3.1 — locked under
    a wrapped key on both clients).

### Still open

A. **Server-side delivery telemetry granularity.** `MarkDeliveryAttempted`
   writes one row per (message, device). For a heavily-active user, this
   is the same row count as messages × device-fan-out. Probably fine;
   worth a load-test in the integration suite. Alternative: a single
   counter column on `message` (`delivered_device_count`), incremented
   atomically. *Recommendation: stick with the join table — it makes
   the prune predicate trivially correct and the audit story honest.*

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
- **NO OVERENGINEERING — concrete corrections in this revision.**
  - **12 ports → 6.** Dropped `IMessageValidator`,
    `IMessagePersister`, `IBroadcaster`, `IConversationFactory`,
    `INotificationDispatcher`, `IRateLimitPolicy` — each had a single
    default impl and no concrete S28.3b consumer. The cost of an
    abstraction with one impl is pure overhead. Add the port when a
    second consumer materialises.
  - **3 capability endpoints → 1.** `/limits` + `/capabilities` +
    `/me/capabilities` was three GETs carrying overlapping data. Now
    `/limits` + `/capabilities[?me=true]` — two endpoints, no shape
    duplication.
  - **No `meinchat-enterprise` surface drafted.** Carries no concrete
    consumer this turn; the port surface is general enough to host one
    later. Validators-for-DLP, persister-for-archive-mirror,
    broadcasters-for-webhooks remain non-extracted abstractions.
  - **No chain-of-responsibility codecs.** Single-codec keeps the
    decryption path deterministic and the `protocol` column unambiguous.
    Compress-before-encrypt is a future port (with consumer) if/when needed.
  - **No server-side ratchet state.** Dropped along with the
    server-side encryptor — the server is a forwarder. Removes a whole
    `SignalProtocolStore` subsystem from the backend dependency graph.
- **DRY — concrete corrections.**
  - **One resolver pair** (`resolve_first` / `resolve_all`) backs every
    port; matches the existing `paymentDataContributors` pattern.
  - **One `NoDeviceKeysError`** lives in meinchat (the base) and is
    re-used by both the body codec (S28.3b) and the attachment codec
    (S28.4). No per-plugin redefinition.
  - **One `RetentionService`** powers both the daily cron and the
    manual `make meinchat-prune` Makefile target; the prune predicate
    `should_prune(message, now)` is the single home for the
    delivered-or-plain rule (S28.1).
  - **One delivery-tracking table** drives both the prune-predicate and
    a future "delivered to N/M devices" UX hint — no shadow counter.
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
