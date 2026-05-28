# S28.3b — `meinchat-plus` plugin (Signal ratchet + device directory + prekey bundles)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
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
who both have a registered device key get their messages
end-to-end encrypted; the server stores ciphertext only.

meinchat itself is **not modified** in this slice — every change lives
in the three new plugin repos. meinchat-plus declares
`dependencies = ["meinchat"]` and registers against the ports
S28.3a extracted.

## 2. Backend — `vbwd-plugin-meinchat-plus`

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

```sql
-- One row per user device (web tab on a fingerprintable browser, iOS install, Android install).
CREATE TABLE meinchat_plus_user_device_key (
    id           UUID PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES vbwd_user(id) ON DELETE CASCADE,
    public_key   BYTEA NOT NULL,          -- 32 bytes X25519
    algorithm    VARCHAR(64) NOT NULL DEFAULT 'curve25519_xchacha20poly1305_v1',
    label        VARCHAR(128),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at   TIMESTAMPTZ NULL,
    CONSTRAINT meinchat_plus_user_device_key_user_label_uq UNIQUE (user_id, label)
);

CREATE INDEX meinchat_plus_user_device_key_active_idx
    ON meinchat_plus_user_device_key (user_id) WHERE revoked_at IS NULL;

-- One-time prekey bundle entries; consumed on first message to an offline device.
CREATE TABLE meinchat_plus_prekey_bundle (
    id             UUID PRIMARY KEY,
    device_id      UUID NOT NULL REFERENCES meinchat_plus_user_device_key(id) ON DELETE CASCADE,
    signed_prekey  BYTEA NOT NULL,
    one_time_prekey BYTEA NOT NULL,
    signature      BYTEA NOT NULL,
    consumed_at    TIMESTAMPTZ NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Migration lives in `meinchat-plus/migrations/versions/` per the existing
"plugin migrations live in the plugin" convention. Registered in
`alembic.ini` `version_locations` (the recipe will pick it up when
`make up` rebuilds).

### 2.4 IBodyCodec impl (`SignalRatchetCodec`)

`services/signal_codec.py`:

```python
from signal_protocol import storage, helpers

class SignalRatchetCodec(IBodyCodec):
    def __init__(self, store: storage.InMemorySignalProtocolStore | DurableStore, *, …): …

    def encode(self, ctx: SendContext) -> EncodedBody:
        recipients = resolve_first(IDeviceDirectory).lookup_active(ctx.recipients[0].id)
        if not recipients:
            raise NoDeviceKeysError(...)            # strict fallback (decision in §11.1 of parent sprint)
        envelopes = []
        for device in recipients:
            cipher = helpers.encrypt(self.store, ctx.body_or_envelope, device.public_key, ...)
            envelopes.append(cipher)
        # Concatenate envelopes with a small header so the read side can pick
        # the one addressed to its device.
        return EncodedBody(body=None, envelope=pack(envelopes), protocol="e2e_v1")

    def decode(self, row: Message, viewer_device: Device | None) -> str:
        if viewer_device is None:
            raise CannotDecryptError("no viewer device registered")
        return helpers.decrypt(self.store, row.envelope, viewer_device.private_key, ...)
```

`SendContext.body_or_envelope` is plaintext on the way in (the
plugin's web/iOS client passes the user-typed body) and the codec
seals it. On the way out, the route handler resolves the *viewer's*
device (from a session-scoped middleware that attaches
`request.user_device` based on the bearer's claimed device id) and
passes it to `decode`.

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

### 2.7 IConversationCapabilities impl

```python
class E2eV1Capability(IConversationCapabilities):
    def for_conversation(self, conv: Conversation) -> set[str]:
        return {"e2e_v1"}
```

### 2.8 Routes

`routes.py`:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/messaging/me/devices` | Publish this device's X25519 public key + label. Rate-limited (`device_registration`, default `5 / hour`). |
| `GET` | `/api/v1/messaging/users/<user_id>/devices` | List active devices for the peer, so the sender can fan out envelopes. Rate-limited (`device_lookup`, default `60 / hour`). |
| `DELETE` | `/api/v1/messaging/me/devices/<device_id>` | Revoke; sets `revoked_at`. Idempotent. |
| `POST` | `/api/v1/messaging/me/prekeys` | Upload N one-time prekey bundles (default 100, refilled when consumed). |
| `GET` | `/api/v1/messaging/devices/<device_id>/prekey-bundle` | Consume one prekey bundle for async first-message bootstrap. Atomic — marks `consumed_at`. |

Rate-limit categories are registered with meinchat's existing
`IRateLimitPolicy` (S26 pattern), so admins tune them per-instance.

### 2.9 `on_enable` registers everything

```python
def on_enable(self) -> None:
    super().on_enable()
    register(IBodyCodec, SignalRatchetCodec(self.store))
    register(IDeviceDirectory, UserDeviceKeyDirectory(self._session_factory))
    register(IConversationPolicy, BothPeersHaveDeviceKeys())
    register(IConversationCapabilities, E2eV1Capability())
    register(IPostSendHook, RotateRatchetState(self.store))
```

`on_disable` reverses every register via a corresponding `unregister`
helper that the S28.3a registry exposes — meinchat falls back to its
identity/null defaults cleanly. Liskov guard.

### 2.10 Backend tests

#### `tests/unit/services/test_signal_codec.py` (NEW, ≥ 8 specs)

| # | Spec |
|---|---|
| 1 | Encrypt → decrypt round-trip with matched key |
| 2 | Decrypt with mismatched key raises (ChaChaPoly auth fail) |
| 3 | Tamper a single byte of envelope → decrypt raises |
| 4 | Multi-recipient fan-out: one plaintext → N envelopes, each opens only with its key |
| 5 | Recipient with no device key → `encode` raises `NoDeviceKeysError` (strict fallback) |
| 6 | Re-encoding the same plaintext produces different ciphertext (nonce uniqueness) |
| 7 | Codec replaces the default identity codec via `register`; `resolve_first(IBodyCodec)` returns the Signal impl |
| 8 | On `on_disable`, the default identity codec is restored |

#### `tests/unit/services/test_device_directory.py` (NEW, ≥ 6 specs)

Registration, lookup_active (excludes revoked), revoke is idempotent,
`has_any` returns the right boolean, label uniqueness per user is enforced.

#### `tests/unit/services/test_prekey_service.py` (NEW, ≥ 5 specs)

Bulk upload, consume one (`consumed_at` set, single row affected),
concurrent consume returns different rows (advisory lock or `FOR UPDATE
SKIP LOCKED` — pick whichever the codec library prefers), refill when
< N remaining triggers a "refill needed" signal client-side.

#### `tests/unit/policies/test_both_have_keys_policy.py` (NEW, ≥ 4 specs)

Both peers with keys → pass; peer without → raise `PolicyError` with
the documented hint; deletion of the only key → next attempt vetoes.

#### `tests/integration/test_e2e_round_trip.py` (NEW, ≥ 3 specs)

End-to-end against real PG + the meinchat read/write routes:

1. Two test users + one device each → register keys → start
   conversation → send a message → the row in `message` has
   `protocol='e2e_v1'`, `envelope IS NOT NULL`, `body=''`.
2. The recipient's `GET /messages?conversation_id=...` returns the
   decrypted plaintext to the recipient device.
3. The sender's same request — also decryptable (the sender's device
   is a recipient too, by design).

**Critical assertion baked into the integration test:** after the
write, do a raw `SELECT body FROM message WHERE id=...` and assert
the plaintext bytes do NOT appear in the result. Catches any
accidental persisted-plaintext regression.

## 3. Web — `vbwd-fe-user-plugin-meinchat-plus`

### 3.1 Crypto

- `tweetnacl-js` for X25519 + ChaChaPoly primitives.
- `@signalapp/libsignal-client` (JS bindings) for the ratchet.

### 3.2 Storage

- IndexedDB store keyed by `(user_id, device_id)` holding the device's
  private key + ratchet state.
- Private key wrapped under a WebCrypto `CryptoKey` with
  `extractable=false` where supported (modern Chrome/Safari/Firefox).
  Fallback: a passphrase-derived key (Argon2 if `argon2-browser` is
  acceptable; else PBKDF2 — out of scope to debate, default to PBKDF2
  300k iters).

### 3.3 Registration flow

On first plugin enable:

1. Generate keypair via WebCrypto.
2. `POST /me/devices` with the public key + a label (defaults to
   `Chrome on macOS`-style UA stamp, user-editable).
3. `POST /me/prekeys` with 100 freshly minted prekey bundles.
4. Surface a "Secure chat ready" toast.

### 3.4 Send flow integration

`useMeinchatStore.sendText` is unchanged — meinchat-plus intercepts via
the BodyCodec port. But the web plugin contributes a small
**conversation precheck**: before letting the user click Send, query
`/api/v1/messaging/users/<peer_id>/capabilities` (existing in 3a). If
the peer's capabilities include `e2e_v1`, render a small lock badge
near the composer. If not, render a "Ask @bob to enable secure chat"
hint and disable Send.

### 3.5 Tests

- `plugins/meinchat-plus/tests/unit/crypto/round-trip.spec.ts` ≥ 4 specs.
- `plugins/meinchat-plus/tests/unit/store/key-registration.spec.ts` ≥ 3 specs.
- `plugins/meinchat-plus/tests/unit/components/composer-precheck.spec.ts` ≥ 3 specs.

## 4. iOS — `vbwd-ios-plugin-meinchat-plus`

### 4.1 Crypto

- CryptoKit `Curve25519.KeyAgreement` for X25519.
- `LibSignalClient` Swift package for the ratchet.

### 4.2 Storage

- Private keys in Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (decision §11.2 of
  parent sprint).
- Ratchet state in CoreData entity `RatchetSession` (separate from the
  S28.2 `CachedMessage` entity — different concerns).

### 4.3 Registration flow

`AppDelegate`-time check on first launch after the plugin is enabled:
generate, register, upload prekeys. Same shape as web.

### 4.4 Tests

- `Tests/MeinChatPlusPluginTests/EnvelopeRoundTripTests.swift` ≥ 4 specs.
- `Tests/MeinChatPlusPluginTests/KeyRegistrationFlowTests.swift` ≥ 3 specs.
- `Tests/MeinChatPlusPluginTests/ComposerPrecheckTests.swift` ≥ 3 specs.

## 5. Acceptance criteria

- Backend integration `test_e2e_round_trip.py` GREEN — the persisted
  `body` column does not contain any plaintext bytes from the sent
  message; the recipient route still returns the plaintext to the
  decrypting device.
- Two human users on the same instance, one on web + one on iOS, can
  exchange messages end-to-end; ciphertext-only on the wire (verified
  by `tcpdump`-on-loopback during a manual smoke).
- Disabling meinchat-plus via the admin UI restores plaintext flow
  cleanly — no orphaned tables blocking re-enable later (verified by
  a migration up-down-up oracle).
- `bin/pre-commit-check.sh --plugin meinchat-plus --full` GREEN on the
  backend; fe-user + iOS CIs GREEN on the matching plugin repos.
- A sender attempting to message a peer with no device key receives
  the documented `code="peer_has_no_device_keys"` error + hint
  (strict fallback per §11.1 of the parent sprint).

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

- **TDD-first:** ≥ 30 new specs across backend + web + iOS. The
  integration tests are characterisation in the strongest sense — the
  raw-SQL assertion "no plaintext on disk" can't be silently regressed.
- **DevOps-first:** new plugin repos get their own CI from day one
  (mirrors the `vbwd-plugin-token-payment` rollout). Migration
  up-down-up oracle in CI.
- **SOLID — S:** each registered impl has one job. `SignalRatchetCodec`
  doesn't know about device directories; it asks the resolver.
- **SOLID — O:** zero meinchat changes. The whole feature is additive
  via the ports.
- **SOLID — L:** disabling meinchat-plus restores meinchat's defaults
  cleanly (`on_disable` `unregister`-s every contribution). Substitutability
  preserved.
- **SOLID — I:** `IDeviceDirectory` has 4 methods; codec has 2; policy
  has 1. No fat ports.
- **SOLID — D:** every collaborator (libsignal store, session factory,
  config) is injected at the plugin's `__init__`. No module-level
  state outside the registry itself.
- **DRY:** the plugin's tables + migrations live in its own repo; we
  do not duplicate the meinchat session bootstrap.
- **NO OVERENGINEERING:** sticking to 1:1, no Sender Keys yet, no
  recovery flow, no tier gating. Each is a clear follow-up.
- **Core agnostic:** meinchat is untouched in this slice — the entire
  feature lives in `meinchat-plus`. meinchat-plus depends on
  `meinchat`, which is the existing dependency pattern.
