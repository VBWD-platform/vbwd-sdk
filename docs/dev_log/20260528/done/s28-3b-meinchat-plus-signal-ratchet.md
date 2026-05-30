# S28.3b — `meinchat-plus` plugin (Signal ratchet + device directory + prekey bundles)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb the
critical review:
- Server-side `SignalRatchetCodec.encode` saw plaintext → **encryption
  moved to the client**; server-side codec is now a `SignalEnvelopeValidator`
  (validates shape + size, no keys).
- Ciphertext length leaked plaintext length → **256-byte padding** before
  encrypt.
- Prekey race could repeat the chain key → **`SELECT … FOR UPDATE SKIP
  LOCKED`** locked in.
- `prekey_bundle` conflated signed + one-time prekeys → **split into two
  tables** (Signal-spec compliant).
- Protocol downgrade was undefended → **client fail-closed** when
  `accepted_protocols=["e2e_v1"]` and response `protocol != "e2e_v1"`.
- Sender unable to decrypt own messages on a second device → **recipient
  set includes sender's own devices**, fan-out is client-side.
- Retention prune deleted undelivered async messages → **delivery
  tracking** via `meinchat_plus_message_delivery`; S28.1 exempts
  not-yet-delivered E2E rows.
**Depends on:** [S28.3a](s28-3a-meinchat-extension-ports.md) (uses the six ports + the schema columns).
**Blocks:** [S28.4](s28-4-attachment-encryption.md) (mirrors the pattern on attachments).

**Repos touched — all NEW (3 standalone plugin repos):**
- `vbwd-plugin-meinchat-plus` (backend).
- `vbwd-fe-user-plugin-meinchat-plus` (web).
- `vbwd-ios-plugin-meinchat-plus` (iOS).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --plugin meinchat-plus --full` GREEN on backend; fe-user plugin CI GREEN; iOS package CI GREEN.

---

## 1. Goal

Ship Constellation A (Signal double-ratchet, libsignal-protocol) as an
opt-in plugin on top of meinchat. When enabled per-instance, two users
who both have a registered device key exchange messages that the
**client** encrypts before send and the **server** stores opaque (and
broadcasts opaque). The server has no Signal session store, no
encryption code, no decryption code.

meinchat itself is **not modified** in this slice — every change lives
in the three new plugin repos. meinchat-plus declares
`dependencies = ["meinchat"]` and registers against the ports
S28.3a extracted.

**Architecture summary (corrects the earlier draft):**
- **Client** holds the Signal session state, performs encrypt + fan-out,
  and posts a single CBOR-packed `envelope` blob.
- **Server** validates the blob shape + size, stores it, broadcasts it,
  and tracks per-device fetch progress so S28.1 can prune delivered
  rows safely. **The server never holds plaintext.**

## 2. Backend — `vbwd-plugin-meinchat-plus`

### 2.0 Repo posture — **public from day one** (S28 decision R4-Q1)

The three new plugin repos (`vbwd-plugin-meinchat-plus`,
`vbwd-fe-user-plugin-meinchat-plus`, `vbwd-ios-plugin-meinchat-plus`)
are created **public** under the `VBWD-platform` GitHub org from
their first commit — not flipped public at launch. Open-source
posture matches the existing plugin repos.

Implementation discipline this imposes:

- **Feature branches for half-implementations.** `main` is never
  half-broken; landed PRs are reviewable end-to-end. WIP lives on
  feature branches.
- **No secrets in test fixtures.** Test JWTs use the dev-secret
  documented in CLAUDE.md; no real keys, no internal hostnames, no
  production env values. Pinned by a CI grep job (`scripts/no-secrets-lint.sh`).
- **Commit messages are user-visible.** No internal Slack
  references, ticket numbers from a private tracker, or operator
  names. Reference public issues + sprint docs only.
- **Audit-friendly history.** External eyes can read the full
  development trajectory; no squash-merge to hide refactor steps.
  Squash only at PR boundaries where the squashed commit is itself
  a clean, reviewable unit.

This decision also enables the deferred audit option (R3-Q1) without
NDA friction — auditors can clone the repo directly when the
implementation is ready.

### 2.1 Plugin scaffold

Mirror the `vbwd-plugin-token-payment` repo's shape:

```
vbwd-plugin-meinchat-plus/
├── __init__.py                         # MeinChatPlusPlugin(BasePlugin)
├── meinchat_plus/
│   ├── models/
│   │   ├── user_device_key.py          # X25519 public-key registry per user
│   │   └── prekey_bundle.py            # one-time prekeys for async first messages
│   ├── repositories/
│   │   ├── device_repository.py
│   │   └── prekey_repository.py
│   ├── services/
│   │   ├── signal_codec.py             # IBodyCodec impl wrapping libsignal
│   │   ├── device_directory.py         # IDeviceDirectory impl
│   │   └── prekey_service.py
│   ├── routes.py                       # /me/devices, /users/{id}/devices, /me/prekeys
│   └── policies/
│       └── both_have_keys_policy.py    # IConversationPolicy impl
├── migrations/versions/
│   └── 20260601_xxxx_create_meinchat_plus_tables.py
├── config.json
├── admin-config.json
├── tests/
│   ├── unit/
│   └── integration/
├── README.md
└── docs/
```

### 2.2 `PluginMetadata`

```python
PluginMetadata(
    name="meinchat-plus",
    version="1.0.0",
    description="E2E-encrypted chat — Signal-style ratchet on top of meinchat.",
    dependencies=["meinchat"],
    extension_points=[
        "IBodyCodec", "IDeviceDirectory", "IConversationPolicy",
        "IConversationCapabilities", "IPostSendHook"
    ],
)
```

`PluginManager` already refuses to enable a plugin whose dependencies
aren't enabled (`manager.py:114-118`) and refuses to disable a plugin
that another depends on (`:189-197`). No new core code needed.

### 2.3 Schema (new tables — owned by meinchat-plus)

The earlier draft conflated signed prekeys and one-time prekeys into
one `prekey_bundle` table; that masked the different rotation
lifecycles (signed prekeys are long-lived per device + periodically
rotated; one-time prekeys are single-use). **Split into two tables**
in this revision — DRY corollary: each row models one Signal-protocol
concept.

```sql
-- One row per user device (web tab on a fingerprintable browser, iOS
-- install, Android install).
CREATE TABLE meinchat_plus_user_device_key (
    id           UUID PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES vbwd_user(id) ON DELETE CASCADE,
    public_key   BYTEA NOT NULL,          -- 32 bytes X25519 identity key
    algorithm    VARCHAR(64) NOT NULL DEFAULT 'curve25519_xchacha20poly1305_v1',
    label        VARCHAR(128),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at   TIMESTAMPTZ NULL,
    CONSTRAINT meinchat_plus_user_device_key_user_label_uq UNIQUE (user_id, label)
);

CREATE INDEX meinchat_plus_user_device_key_active_idx
    ON meinchat_plus_user_device_key (user_id) WHERE revoked_at IS NULL;

-- Long-lived per-device signed prekey. One *active* row per device;
-- replaced on rotation (the client uploads a fresh one and we delete
-- the previous active row). Carries a signature by the device's
-- identity key so the recipient verifies authenticity.
CREATE TABLE meinchat_plus_signed_prekey (
    id            UUID PRIMARY KEY,
    device_id     UUID NOT NULL REFERENCES meinchat_plus_user_device_key(id) ON DELETE CASCADE,
    signed_prekey BYTEA NOT NULL,
    signature     BYTEA NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    rotated_at    TIMESTAMPTZ NULL,        -- when superseded; lookup ignores rows with rotated_at IS NOT NULL
    CONSTRAINT meinchat_plus_signed_prekey_one_active_per_device
        EXCLUDE (device_id WITH =) WHERE (rotated_at IS NULL)
);

-- Single-use one-time prekeys. Consumed atomically via
-- `SELECT … FOR UPDATE SKIP LOCKED` (see prekey_service in §2.8).
-- Closes the race-condition forward-secrecy break flagged by the
-- critical review.
CREATE TABLE meinchat_plus_one_time_prekey (
    id          UUID PRIMARY KEY,
    device_id   UUID NOT NULL REFERENCES meinchat_plus_user_device_key(id) ON DELETE CASCADE,
    prekey      BYTEA NOT NULL,
    consumed_at TIMESTAMPTZ NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX meinchat_plus_one_time_prekey_unconsumed_idx
    ON meinchat_plus_one_time_prekey (device_id) WHERE consumed_at IS NULL;

-- Delivery tracking — one row per (message, addressed device) pair.
-- Read by S28.1's `E2eAwareRetentionPolicy` to exempt undelivered
-- rows from the prune.
CREATE TABLE meinchat_plus_message_delivery (
    message_id  UUID NOT NULL REFERENCES message(id) ON DELETE CASCADE,
    device_id   UUID NOT NULL REFERENCES meinchat_plus_user_device_key(id) ON DELETE CASCADE,
    fetched_at  TIMESTAMPTZ NULL,
    PRIMARY KEY (message_id, device_id)
);

CREATE INDEX meinchat_plus_message_delivery_undelivered_idx
    ON meinchat_plus_message_delivery (message_id) WHERE fetched_at IS NULL;
```

Migration lives in `meinchat-plus/migrations/versions/` per the existing
"plugin migrations live in the plugin" convention. Registered in
`alembic.ini` `version_locations` (the recipe will pick it up when
`make up` rebuilds).

### 2.4 IBodyCodec impl (`SignalEnvelopeValidator`) — no keys, no encryption

The earlier draft ran libsignal-encrypt on the server, which meant the
plaintext was visible to the api process during encode. That's not
E2E — it's at-rest encryption with a Signal label. **This revision
moves all crypto to the client.** The server-side codec is a thin
validator: it ensures the envelope is well-formed and within size
limits, and otherwise treats the bytes as opaque.

`services/signal_envelope_validator.py`:

```python
import cbor2
from plugins.meinchat.meinchat.extensibility.pipeline import (
    IBodyCodec, EncodedBody, SendContext,
)


class InvalidEnvelopeError(Exception):
    """Server-side validation failure on a meinchat-plus envelope."""


class EnvelopeTooLargeError(InvalidEnvelopeError): ...
class UnknownRecipientDeviceError(InvalidEnvelopeError): ...
class MalformedEnvelopeError(InvalidEnvelopeError): ...


class SignalEnvelopeValidator(IBodyCodec):
    """Server-side IBodyCodec impl: validates client-produced ciphertext.
    Holds no keys, performs no encryption, performs no decryption."""

    def __init__(self, *, max_size: int) -> None:
        self._max_size = max_size

    def encode(self, ctx: SendContext) -> EncodedBody:
        envelope = ctx.body_or_envelope
        if not isinstance(envelope, (bytes, bytearray)):
            raise MalformedEnvelopeError("envelope must be bytes")
        if len(envelope) > self._max_size:
            raise EnvelopeTooLargeError(
                f"envelope is {len(envelope)} bytes; max {self._max_size}"
            )
        # Parse the CBOR header WITHOUT decoding any ciphertext.
        try:
            decoded = cbor2.loads(bytes(envelope))
        except cbor2.CBORDecodeError as exc:
            raise MalformedEnvelopeError(str(exc)) from exc
        if not isinstance(decoded, dict) or decoded.get("v") != 1:
            raise MalformedEnvelopeError("missing or unsupported version tag")
        slots = decoded.get("per_recipient")
        if not isinstance(slots, list) or not slots:
            raise MalformedEnvelopeError("per_recipient must be a non-empty list")
        seen_device_ids: set[bytes] = set()
        for slot in slots:
            if not isinstance(slot, dict):
                raise MalformedEnvelopeError("recipient slot must be a map")
            for key in ("device_id", "ciphertext", "header"):
                if key not in slot:
                    raise MalformedEnvelopeError(f"recipient slot missing {key!r}")
                if not isinstance(slot[key], (bytes, bytearray)):
                    raise MalformedEnvelopeError(f"recipient slot {key} must be bytes")
            device_id = bytes(slot["device_id"])
            if device_id in seen_device_ids:
                raise MalformedEnvelopeError("duplicate device_id in recipient slots")
            seen_device_ids.add(device_id)
            if device_id not in ctx.expected_device_ids:
                raise UnknownRecipientDeviceError(device_id.hex())
        # Round-trip the envelope unchanged. The server never decodes.
        return EncodedBody(body=None, envelope=bytes(envelope), protocol="e2e_v1")

    def decode(self, row: Message, viewer_device: Device | None) -> str:
        # The server never decodes — clients pick their own per-recipient
        # slot from `row.envelope` and decrypt locally. The route handler
        # returns the raw bytes; this method is never called server-side
        # for e2e_v1 rows.
        raise NotImplementedError("decode is client-side only for e2e_v1")
```

`SendContext.body_or_envelope` for an `e2e_v1` send is **already
ciphertext** — the meinchat-plus client encrypted it and posted the
CBOR-packed envelope. `SendContext.expected_device_ids` is populated
by the meinchat route handler from `IDeviceDirectory.lookup_active`
on the conversation participants (peer's devices + sender's own
devices); the validator rejects envelopes addressed to devices the
server doesn't know about (defence-in-depth against a misbehaving
client).

**Plaintext never enters the api process.** The route handler reads
`request.json["envelope_b64"]` (base64-encoded ciphertext) and passes
the bytes straight into `SendContext.body_or_envelope`. The earlier
field `request.json["body"]` is rejected for `e2e_v1` conversations.

**Reading side.** `GET /messages/<conv_id>?since=…` returns the raw
`envelope` column (base64). The client unpacks the CBOR, picks the
slot whose `device_id` matches its own, and decrypts. The route
handler also fires `IPostSendHook.on_sent` (which `MarkDeliveryAttempted`
listens to) with the fetching device's id so the
`meinchat_plus_message_delivery` row is updated — see §2.7 below.

### 2.5 IDeviceDirectory impl (`UserDeviceKeyDirectory`)

`services/device_directory.py` — straightforward SQLAlchemy implementation
over `meinchat_plus_user_device_key`. Replaces meinchat's
`NullDeviceDirectory` on enable.

### 2.6 IConversationPolicy impl (`BothPeersHaveDeviceKeys`)

```python
class BothPeersHaveDeviceKeys(IConversationPolicy):
    """Veto starting a conversation with a peer who has no active device key.
    Surfaces a UI hint via the standard error envelope so the client can
    show: 'Ask @bob to enable secure chat on a device.'"""
    def may_start(self, initiator: User, peer: User) -> None:
        directory = resolve_first(IDeviceDirectory)
        if not directory.has_any(peer.id):
            raise PolicyError(
                code="peer_has_no_device_keys",
                hint=f"Ask @{peer.nickname} to enable secure chat on a device.",
            )
```

### 2.7 IConversationCapabilities + IPostSendHook impls

```python
class E2eV1Capability(IConversationCapabilities):
    def for_conversation(self, conv: Conversation) -> set[str]:
        return {"e2e_v1"}


class MarkDeliveryAttempted(IPostSendHook):
    """Closes the 'retention prune deletes undelivered E2E rows' bug.

    On every authenticated GET /messages/<conv_id>?since=… that returns
    e2e_v1 rows, this hook inserts one
    `meinchat_plus_message_delivery (message_id, device_id, fetched_at)`
    row per (returned message, fetching device) pair — idempotent under
    the composite PK. When the count of rows with `fetched_at IS NOT NULL`
    equals the count of slots in `envelope.per_recipient`, it sets
    `message.delivered_to_all_addressed_devices_at = now()`.

    S28.1's `E2eAwareRetentionPolicy` reads that column to exempt
    not-yet-delivered E2E rows from the prune.
    """

    def __init__(self, delivery_repo: MessageDeliveryRepository) -> None: ...

    def on_sent(self, row: Message, *, fetched_by: Device | None = None) -> None:
        if row.protocol == "plain":
            return                           # plain rows are delivered as soon as written
        if fetched_by is None:
            return                           # SSE broadcasts don't count as delivery
        self._delivery_repo.mark_fetched(row.id, fetched_by.id)
        if self._delivery_repo.all_addressed_devices_have_fetched(row.id):
            self._delivery_repo.mark_delivered_to_all(row.id, at=now_utc())
```

### 2.8 Routes

`routes.py`:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/messaging/me/devices` | Publish this device's X25519 public key + label. Server stores; **does not generate keys**. Rate-limited (`device_registration`, default `5/h`). |
| `GET` | `/api/v1/messaging/users/<user_id>/devices` | List active devices (+ public keys) for the peer so the **sender** can fan out envelopes client-side. Rate-limited (`device_lookup`, default `60/h`). |
| `DELETE` | `/api/v1/messaging/me/devices/<device_id>` | Revoke; sets `revoked_at`. Idempotent. |
| `POST` | `/api/v1/messaging/me/prekeys/signed` | Upload / rotate the device's signed prekey. Server verifies the signature against the device's identity key before accepting. |
| `POST` | `/api/v1/messaging/me/prekeys/one-time` | Upload N one-time prekeys (default 100). Refilled when count drops below 20 (signalled via response header `X-Prekey-Low-Water: true`). |
| `GET` | `/api/v1/messaging/devices/<device_id>/prekey-bundle` | Atomically consume one one-time prekey + return the active signed prekey + the device's identity public key. Implementation locked in this revision (see below). |

Rate-limit categories are registered with meinchat's existing S26 plugin
config, so admins tune them per-instance. The `IRateLimitPolicy` port
is NOT re-introduced in meinchat-plus — meinchat's existing config
keys (S26) cover the surface; adding categories is a config-only change.

**Prekey consumption — locked to `FOR UPDATE SKIP LOCKED`** (closes the
race the critical review flagged):

```python
def consume_one_time_prekey(self, device_id: UUID) -> bytes | None:
    """Atomically pick + mark one unconsumed one-time prekey for a
    device. Two concurrent callers MUST receive different rows; if
    no rows remain, returns None (the client should refill)."""
    return self._session.execute(text(
        """
        UPDATE meinchat_plus_one_time_prekey
           SET consumed_at = now()
         WHERE id = (
             SELECT id FROM meinchat_plus_one_time_prekey
              WHERE device_id = :device_id AND consumed_at IS NULL
              ORDER BY created_at
              FOR UPDATE SKIP LOCKED
              LIMIT 1
         )
        RETURNING prekey
        """
    ), {"device_id": device_id}).scalar_one_or_none()
```

The integration spec asserts that two concurrent sessions consuming
against the same device id receive different (non-null) prekeys — pins
the forward-secrecy guarantee.

### 2.9 `on_enable` registers everything (six concrete impls — no speculative ports)

```python
def on_enable(self) -> None:
    super().on_enable()
    register(IBodyCodec, SignalEnvelopeValidator(max_size=self._cfg.ciphertext_max_bytes))
    register(IDeviceDirectory, UserDeviceKeyDirectory(self._session_factory))
    register(IConversationPolicy, BothPeersHaveDeviceKeys())
    register(IConversationCapabilities, E2eV1Capability())
    register(IPostSendHook, MarkDeliveryAttempted(self._delivery_repo))
    register(IRetentionPolicy, E2eAwareRetentionPolicy(self._delivery_repo, self._cfg))
```

No server-side Signal session store, no `SignalProtocolStore`
dependency in the backend, no `RotateRatchetState` — ratchet state
lives on the clients (S28.3b §3/§4).

`on_disable` reverses every register via a corresponding `unregister`
helper that the S28.3a registry exposes — meinchat falls back to its
identity/null defaults cleanly. Liskov guard.

### 2.10 Backend tests

#### `tests/unit/services/test_signal_envelope_validator.py` (NEW, ≥ 8 specs)

Server-side specs only test the validator — no Signal session state on
the server. (Client-side encrypt/decrypt round-trip lives in §3.5 +
§4.4.)

| # | Spec |
|---|---|
| 1 | Well-formed envelope with one recipient slot → `encode` returns `EncodedBody(envelope=…, protocol="e2e_v1")` round-tripping the bytes unchanged |
| 2 | Envelope > `ciphertext_max_bytes` → `EnvelopeTooLargeError` |
| 3 | Non-bytes input → `MalformedEnvelopeError` |
| 4 | Missing `v` tag or wrong version → `MalformedEnvelopeError` |
| 5 | Recipient slot missing `device_id` / `ciphertext` / `header` → `MalformedEnvelopeError` |
| 6 | Duplicate device_id across slots → `MalformedEnvelopeError` |
| 7 | Slot with a device_id not in `ctx.expected_device_ids` → `UnknownRecipientDeviceError` (defence-in-depth) |
| 8 | `decode(row, viewer_device)` always raises `NotImplementedError` for e2e_v1 — server never decrypts |

#### `tests/unit/services/test_device_directory.py` (NEW, ≥ 6 specs)

Registration, lookup_active (excludes revoked), revoke is idempotent,
`has_any` returns the right boolean, label uniqueness per user is enforced.

#### `tests/unit/services/test_signed_prekey_service.py` (NEW, ≥ 5 specs)

Upload (server verifies the signature against the device identity key),
rotation supersedes the previous active row (`rotated_at` set, EXCLUDE
constraint keeps "one active per device" invariant), an invalid
signature is rejected with 400, lookup returns the active row only.

#### `tests/unit/services/test_one_time_prekey_service.py` (NEW, ≥ 5 specs)

Bulk upload, single consume (`consumed_at` set, the row's prekey is
returned), refill signal triggers when count drops below 20.

The **race spec** is the headline:

```python
def test_concurrent_consume_returns_distinct_prekeys(self, db_session_factory):
    """Closes the Signal forward-secrecy break the critical review
    flagged: two senders to the same offline recipient MUST receive
    different one-time prekeys."""
    seed_one_time_prekeys(device_id, count=5)
    results: list[bytes | None] = []
    barrier = threading.Barrier(2)

    def consumer() -> None:
        session = db_session_factory()
        try:
            barrier.wait()
            results.append(OneTimePrekeyService(session).consume(device_id))
            session.commit()
        finally:
            session.close()

    t1 = threading.Thread(target=consumer); t2 = threading.Thread(target=consumer)
    t1.start(); t2.start(); t1.join(); t2.join()
    assert all(r is not None for r in results)
    assert results[0] != results[1]
```

#### `tests/unit/policies/test_both_have_keys_policy.py` (NEW, ≥ 4 specs)

Both peers with keys → pass; peer without → raise `PolicyError(code=
"peer_has_no_device_keys", hint=…)` matching the error contract in the
parent sprint's §6; deletion of the only key → next attempt vetoes.

#### `tests/unit/services/test_mark_delivery_attempted.py` (NEW, ≥ 5 specs)

| # | Spec |
|---|---|
| 1 | Plain row → `on_sent` is a no-op |
| 2 | E2E row, fetched_by=None (SSE broadcast) → no row written |
| 3 | E2E row, fetched_by=device A → one delivery row written; `fetched_at IS NOT NULL` |
| 4 | E2E row addressed to 2 devices, only A has fetched → `delivered_to_all_addressed_devices_at IS NULL` |
| 5 | Both A + B have fetched → `delivered_to_all_addressed_devices_at` is set to now() in the same txn |

#### `tests/integration/test_e2e_round_trip.py` (NEW, ≥ 4 specs)

End-to-end against real PG + the meinchat read/write routes, with the
**client side simulated by a thin Python wrapper around libsignal-protocol**
so the test exercises the full client-encrypts → server-validates →
server-stores → client-decrypts flow.

1. Two test users + one device each → register keys + signed + 100
   one-time prekeys → start conversation → the test wrapper encrypts
   client-side and POSTs the envelope → the row in `message` has
   `protocol='e2e_v1'`, `envelope IS NOT NULL`, `body IS NULL`,
   `delivered_to_all_addressed_devices_at IS NULL`.
2. The recipient's `GET /messages?conversation_id=...` returns the raw
   envelope; the test wrapper decrypts using the recipient device's
   private key and asserts plaintext equality. After this fetch, the
   delivery row for `(message_id, recipient_device_id)` has
   `fetched_at IS NOT NULL`.
3. The sender's same request — sender's device is in the recipient list
   (closes critical-review §C7), so the sender can decrypt their own
   message after refetch.
4. After both devices have fetched, `delivered_to_all_addressed_devices_at`
   is non-null and the S28.1 retention prune will treat the row as
   eligible.

**Critical assertions baked in** (catches the regressions the critical
review found):

```python
# 1. Server never saw plaintext during write
raw_body = sql.scalar("SELECT body FROM message WHERE id = :id", id=message_id)
assert raw_body is None, "ciphertext rows must have body IS NULL"

assert b"test_plaintext_marker" not in sql.scalar(
    "SELECT envelope FROM message WHERE id = :id", id=message_id
), "ciphertext envelope must not contain the plaintext marker"

# 2. Ciphertext length is padded to 256B multiple (length-leak protection)
envelope_len = len(sql.scalar("SELECT envelope FROM message WHERE id = :id", id=message_id))
assert envelope_len % 256 == 0, "envelopes must be padded to 256B multiples"

# 3. Downgrade defence — refuse "plain" response when client demanded e2e_v1
response = client.post("/messaging/conversations",
                       json={"peer_nickname": "alice", "accepted_protocols": ["e2e_v1"]},
                       headers=auth_headers(initiator_with_devices))
assert response.status_code == 409
assert response.json["code"] in ("peer_has_no_device_keys", "protocol_negotiation_empty")
```

## 3. Web — `vbwd-fe-user-plugin-meinchat-plus`

The web client holds the Signal session state, runs the ratchet, fans
out to all recipient devices (peer's + sender's own), pads, encrypts,
packs the CBOR envelope, and POSTs.

### 3.1 Crypto

- **`@signalapp/libsignal-client`** (the official JS bindings) for the
  X3DH key agreement + double-ratchet.
- **WebCrypto** for the AEAD primitives where the bindings allow raw
  buffers in.
- **`cbor-x`** (~2 KB minified) for the envelope packing format that
  matches the server-side `SignalEnvelopeValidator` expectation.

### 3.2 Storage

- IndexedDB store keyed by `(user_id, device_id)` holding the device's
  identity private key + Signal session state per peer.
- **At-rest encryption.** Private key is stored **wrapped under a
  passphrase-derived KEK** (Argon2id 64 MB memory / 3 iters where the
  browser supports it via `hash-wasm`; fallback to PBKDF2-SHA-256 600k
  iters per OWASP 2026 minimum). Locked decision in this revision —
  the earlier draft's `WebCrypto extractable=false` is incompatible
  with libsignal-JS's raw-key API (critical review §C17). The KEK is
  derived from a passphrase the user sets at first pairing and
  re-enters on a long-idle return; cached in `sessionStorage` (cleared
  on tab close) so per-send key wrap is one decrypt only.

### 3.3 Registration flow

On first plugin enable:

1. User sets a device passphrase (Argon2id-stretched into the KEK).
2. Generate Signal identity keypair + signed prekey (signed under the
   identity key) + 100 one-time prekeys client-side.
3. `POST /me/devices` with the identity public key + a label.
4. `POST /me/prekeys/signed` with the signed prekey + signature.
5. `POST /me/prekeys/one-time` with the 100 one-time prekeys.
6. Surface a "Secure chat ready" toast.

The server never sees a private key.

### 3.4 Send flow — client-side encrypt + fan-out

`useMeinchatStore.sendText` is overridden by meinchat-plus when the
conversation's `protocol === "e2e_v1"`:

```ts
async function sendE2eText(conv: Conversation, plaintext: string) {
    // 1. Padding — round plaintext (+2 prefix bytes carrying the
    //    original length) to next 256B multiple. Closes the
    //    length-leak the critical review flagged.
    const padded = padTo256(plaintext);
    // 2. Discover ALL addressed devices — peer + own.
    const peerDevices = await api.get(`/messaging/users/${conv.peer_user_id}/devices`);
    const ownDevices  = await api.get(`/messaging/users/${currentUserId}/devices`);
    const addressed   = [...peerDevices, ...ownDevices];
    // 3. Encrypt per device using the Signal session for that pair.
    const slots = await Promise.all(addressed.map(async device => ({
        device_id:  decodeBase64(device.id),
        header:     await sessionFor(device).headerFor(padded),
        ciphertext: await sessionFor(device).encrypt(padded),
    })));
    // 4. Pack as CBOR matching the server-side validator's grammar.
    const envelope = cborEncode({ v: 1, per_recipient: slots });
    // 5. Post.
    return api.post(`/messaging/conversations/${conv.id}/messages`, {
        envelope_b64: base64(envelope),
    });
}
```

### 3.5 Read flow — pick own slot, decrypt locally

```ts
async function decryptIncoming(row: Message) {
    const envelope = decodeBase64(row.envelope_b64);
    const decoded  = cborDecode(envelope);
    const ownSlot  = decoded.per_recipient.find(s =>
        bytesEqual(s.device_id, currentDeviceId));
    if (!ownSlot) throw new Error("no slot addressed to this device");
    const padded   = await sessionFor(senderDevice(row)).decrypt(ownSlot.ciphertext, ownSlot.header);
    return stripPadding(padded);
}
```

### 3.6 Downgrade fail-closed (mandatory)

The web plugin's `startE2eConversation(peer)` posts
`accepted_protocols: ["e2e_v1"]` (refuses plaintext). If the response
`conversation.protocol !== "e2e_v1"`, the plugin throws a
`ProtocolDowngradeError` and surfaces a UI warning. The plugin NEVER
silently falls back to plain mode — closes critical-review §C14.

### 3.7 Composer precheck

Before letting the user click Send on an existing conversation, the
plugin queries `/api/v1/messaging/users/<peer_id>/capabilities` (via
the shared S28.0 capabilities endpoint). If the peer no longer has any
active device keys (e.g. they revoked their only device), the composer
renders a "@<peer> revoked their secure-chat device — wait for them to
re-pair" hint and disables Send.

### 3.8 Tests

- `plugins/meinchat-plus/tests/unit/crypto/padding.spec.ts` ≥ 3 specs
  (round-trip preserves plaintext; padding is multiple of 256; stripping
  recovers original).
- `plugins/meinchat-plus/tests/unit/crypto/round-trip.spec.ts` ≥ 4
  specs (encrypt + decrypt for two-device fan-out; tampered ciphertext
  raises; tampered header raises; envelope-with-unknown-device-id is
  rejected by the server validator in an integration test).
- `plugins/meinchat-plus/tests/unit/store/key-registration.spec.ts` ≥ 3
  specs (registration uploads signed + one-time prekeys; refill on
  low-water response header; user can revoke own device).
- `plugins/meinchat-plus/tests/unit/store/downgrade-fail-closed.spec.ts`
  ≥ 3 specs (response `protocol="plain"` when client demanded
  `["e2e_v1"]` → throws `ProtocolDowngradeError`; UI shows the warning;
  no message is sent on the downgraded conversation).
- `plugins/meinchat-plus/tests/unit/store/own-device-decrypt.spec.ts`
  ≥ 2 specs (sender includes own-devices in fan-out; sender's second
  device can decrypt a message it didn't author).
- `plugins/meinchat-plus/tests/unit/components/composer-precheck.spec.ts`
  ≥ 3 specs (peer has keys → composer enabled; peer revoked → composer
  disabled with hint; transient `/capabilities` error → optimistic
  enable + show the error).

## 4. iOS — `vbwd-ios-plugin-meinchat-plus`

Per [s28-7](s28-7-ios-meinchat-plus-plugin-plan.md) — this section is
the **backend contract** the iOS plugin must implement. Full iOS
delivery plan (incl. integration into the existing
beta-RC `vbwd-ios/VBWD` app) lives in s28-7.

### 4.1 Crypto

- **`LibSignalClient`** Swift package (the official Signal bindings)
  for X3DH + double-ratchet.
- **CryptoKit** for AEAD where the bindings allow raw input.
- **`SwiftCBOR`** for envelope packing (matches the server-side
  validator grammar).

### 4.2 Storage — **biometric primary + passphrase fallback** (S28 decision R1-Q3)

The device identity private key (and Signal session state) is held
in Keychain under **two access-control entries** holding the same
wrapped KEK:

- **Primary entry — biometric-gated.**
  `kSecAccessControlBiometryCurrentSet` + `.userPresence`. Face ID /
  Touch ID required on every read. Zero passphrase friction on the
  happy path. Invalidated automatically on passcode change /
  biometric reset.
- **Fallback entry — passphrase-derived.**
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Sealed under a
  KEK derived from a recovery passphrase the user sets at pairing
  (Argon2id 64 MB / 3 iters — matches the web KEK in §3.2; one
  cross-client parameter set). Used when the primary entry is gone
  (biometric reset, device restore) OR for background tasks that
  must run while the device is locked (S28.2 cache prune, S28.3b
  prekey refill).

Pairing seals the KEK once into both entries. Full UX flow in
[S28.7 §3.1](s28-7-ios-meinchat-plus-plugin-plan.md#31-pairing-viewspairingsheetswift--domaindeviceidentityswift).

- Session state per peer device is wrapped under a per-conversation
  key derived from the identity key via HKDF, so a Keychain dump
  alone doesn't yield session keys without the device identity.

### 4.3 Registration flow

`AppDelegate`-time check on first launch after the plugin is enabled
(see s28-7 §3 for app-level integration details + v1-launch
considerations): generate, register, upload signed + one-time prekeys.
Same shape as web.

### 4.4 Send + read flow

Same client-side encrypt → pad → fan out → CBOR pack → POST as web
(§3.4 / §3.5). Sender includes own active devices in the recipient set.
On read, the iOS client picks its own slot, decrypts, strips padding.

### 4.5 Downgrade fail-closed (mandatory, mirrors §3.6)

`startE2eConversation(peer:)` posts `accepted_protocols: ["e2e_v1"]`;
non-`e2e_v1` response throws `ProtocolDowngradeError` and surfaces a
UI warning.

### 4.6 Tests

- `Tests/MeinChatPlusPluginTests/PaddingTests.swift` ≥ 3 specs.
- `Tests/MeinChatPlusPluginTests/EnvelopeRoundTripTests.swift` ≥ 4
  specs.
- `Tests/MeinChatPlusPluginTests/KeyRegistrationFlowTests.swift` ≥ 3
  specs.
- `Tests/MeinChatPlusPluginTests/DowngradeFailClosedTests.swift` ≥ 3
  specs.
- `Tests/MeinChatPlusPluginTests/OwnDeviceDecryptTests.swift` ≥ 2
  specs.
- `Tests/MeinChatPlusPluginTests/ComposerPrecheckTests.swift` ≥ 3
  specs.

## 5. Acceptance criteria

- Backend integration `test_e2e_round_trip.py` GREEN. The four
  critical assertions in §2.10 all hold:
  - `body IS NULL` for e2e_v1 rows.
  - The plaintext marker bytes do NOT appear anywhere in the persisted
    `envelope` (catches a regression to server-side encryption).
  - `envelope` length is a 256-byte multiple (padding works).
  - Downgrade attempt returns 409 with the documented `code`.
- Two human users on the same instance, one on web + one on iOS, can
  exchange messages end-to-end; ciphertext-only on the wire (verified
  by `tcpdump`-on-loopback during a manual smoke).
- **The sender's second device can decrypt their own sent message**
  after refetch (closes critical-review §C7; pinned by §2.10 test 3).
- **Concurrent prekey consume returns different prekeys** (closes
  critical-review §C13; pinned by §2.10
  `test_concurrent_consume_returns_distinct_prekeys`).
- **Client refuses a downgraded conversation** when it demanded
  `e2e_v1` (closes critical-review §C14; pinned by §3.8
  `downgrade-fail-closed.spec.ts`).
- Disabling meinchat-plus via the admin UI restores plaintext flow
  cleanly — no orphaned tables blocking re-enable later (verified by
  a migration up-down-up oracle).
- `bin/pre-commit-check.sh --plugin meinchat-plus --full` GREEN on the
  backend; fe-user + iOS CIs GREEN on the matching plugin repos.
- A sender attempting to message a peer with no device key receives
  the documented `code="peer_has_no_device_keys"` error + hint
  (strict fallback per §11.1 of the parent sprint).
- **Undelivered e2e_v1 rows survive the S28.1 prune** until every
  addressed device has fetched; once `delivered_to_all_addressed_devices_at`
  is non-null, the row is eligible.

## 6. What this slice explicitly does NOT do

- **Group chats** (Sender Keys layer). Single-recipient (1:1) only.
- **Recovery codes / cross-device history transfer.** A new device
  reads only ciphertext the server has addressed to its new key —
  i.e. nothing before pairing.
- **Tier-gating via the subscription plugin.** Operator-enabled
  per-instance only. Subscription integration is a future slice if
  desired.
- **Push notifications.** A future `meinchat-push` plugin would
  register an `INotificationDispatcher`; out of scope here.
- **Audit log of message events.** Enterprise concern; out of scope.

## 7. Engineering-requirements check

- **TDD-first:** ≥ 40 new specs across backend + web + iOS (up from 30
  in the earlier draft — the race spec, the four critical-assertion
  baked-ins, and the downgrade fail-closed specs are added). Each
  critical-review hole has a named test that would fail if the
  regression returned.
- **DevOps-first:** new plugin repos get their own CI from day one
  (mirrors the `vbwd-plugin-token-payment` rollout). Migration
  up-down-up oracle in CI.
- **SOLID — S:** each registered impl has one job.
  `SignalEnvelopeValidator` validates; `MarkDeliveryAttempted` writes
  delivery rows; `E2eAwareRetentionPolicy` answers prune-eligibility.
  No god class.
- **SOLID — O:** zero meinchat changes. The whole feature is additive
  via the six S28.3a ports.
- **SOLID — L:** disabling meinchat-plus restores meinchat's defaults
  cleanly (`on_disable` `unregister`-s every contribution). The
  identity codec stays a behaviour-preserving substitute of the
  validator (encode = passthrough, decode = passthrough for plain).
- **SOLID — I:** `IDeviceDirectory` has 4 methods; codec has 2; policy
  has 1; post-send-hook has 1. No fat ports.
- **SOLID — D:** every collaborator (delivery repo, session factory,
  config) is injected at the plugin's `__init__`. No module-level
  state outside the registry itself.
- **NO OVERENGINEERING — concrete corrections in this revision.**
  - **No server-side Signal session store.** The earlier draft pulled
    `signal_protocol.storage.InMemorySignalProtocolStore | DurableStore`
    into the backend. Gone. Ratchet state lives on clients; the
    backend has no Signal lib dependency.
  - **No `RotateRatchetState` post-send hook.** Server has no ratchet
    state to rotate. Replaced with `MarkDeliveryAttempted` (a real
    consumer with a real job).
  - **No `IRateLimitPolicy` port re-introduction.** S26's existing
    flat-key config covers `device_registration` / `device_lookup`
    categories without adding a port surface.
  - **No advisory-lock alternative for prekey consume** — `SELECT …
    FOR UPDATE SKIP LOCKED` is locked as the only path. Two options =
    spec gap.
  - **No chain-of-responsibility codec pipeline.** Single codec;
    `protocol` discriminator on the row is the single source of truth.
- **DRY — concrete corrections.**
  - **Prekey table split** (`signed_prekey` + `one_time_prekey`)
    enforces different lifecycle rules at the schema layer instead of
    overloading one table — a row in `signed_prekey` and a row in
    `one_time_prekey` are different concepts; the earlier merged
    `prekey_bundle` table was a DRY violation that hid that.
  - **One `NoDeviceKeysError`** lives in `plugins/meinchat/` (the
    base) and is re-used by both `BothPeersHaveDeviceKeys` (this
    sprint) and the S28.4 attachment codec.
  - **One delivery-tracking table** powers both the prune predicate
    (S28.1) and the "delivered" UX hint (future). No shadow counter on
    `message`.
- **Core agnostic:** meinchat is untouched in this slice — the entire
  feature lives in `meinchat-plus`. meinchat-plus depends on
  `meinchat`, which is the existing dependency pattern.
