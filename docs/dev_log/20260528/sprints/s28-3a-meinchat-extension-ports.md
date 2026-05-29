# S28.3a — meinchat extension ports + schema concessions + capability endpoints (refactor)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb the
critical review:
- Extracted port count cut from 12 → **6** (one port per concrete
  S28.3b consumer; six speculative ports dropped — NO OVERENGINEERING).
- Migration adds `ALTER COLUMN body DROP NOT NULL` so ciphertext rows
  have `body IS NULL` instead of `body = ''` (closes critical-review
  §C5).
- Migration adds `message.delivered_to_all_addressed_devices_at` so
  S28.1's prune can exempt undelivered E2E rows (closes critical-review
  §C20).
- `conversation.protocol` is marked immutable (downgrade defence at
  the schema layer — closes critical-review §C14).
- `POST /messaging/conversations` negotiation-failure contract is now
  defined explicitly (closes critical-review §C6).
- `/messaging/capabilities` + `/messaging/me/capabilities` collapsed
  into one endpoint `/messaging/capabilities[?me=true]` (DRY — closes
  critical-review §"3 capability endpoints → 1").
**Depends on:** S28.0 (config keys + limits endpoint already exist).
**Blocks:** [S28.3b](s28-3b-meinchat-plus-signal-ratchet.md) — meinchat-plus registers against these ports.

**Repos touched:** `vbwd-backend/plugins/meinchat/` only.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --plugin meinchat --full` GREEN; **the new "plugin-free still works" oracle** GREEN.

---

## 1. Goal

The leverage slice. Turns `MessageService.send_text` from a monolithic
method into a thin orchestrator over registered ports. Adds two
columns (`message.envelope`, `message.protocol`) + two on conversation
(`protocol`, `capabilities`). Exposes capability-discovery endpoints.

**External behaviour is unchanged.** With zero downstream plugins
loaded, meinchat's full e2e suite still passes — the refactor is
internal only, with identity/null defaults.

This is what makes S28.3b small (meinchat-plus *only* contributes
registry impls) and what would later make a hypothetical
`meinchat-enterprise` slot in cleanly.

## 2. The six concrete ports

All in a new `plugins/meinchat/meinchat/extensibility/` directory. Each
port has a **named concrete consumer in S28.3b** — nothing speculative.

### 2.1 Pipeline (file: `extensibility/pipeline.py`)

```python
class IBodyCodec(Protocol):
    """Bidirectional transform — encode on send, decode on read.
    Single-impl; last-write-wins. Default in meinchat = identity
    (passthrough). meinchat-plus's `SignalEnvelopeValidator` replaces
    it (server-side; holds no keys, never decrypts)."""
    def encode(self, ctx: SendContext) -> EncodedBody: ...
    def decode(self, row: Message, viewer_device: Device | None) -> str: ...


class IPostSendHook(Protocol):
    """After-the-fact side effects (delivery tracking, analytics).
    Multi-impl; a throwing hook is logged at error, never propagated.
    meinchat-plus registers `MarkDeliveryAttempted` (writes per-device
    fetch progress for the S28.1 prune)."""
    def on_sent(self, row: Message, *, fetched_by: Device | None = None) -> None: ...
```

`SendContext` is a frozen dataclass with `{sender, recipients,
conversation, body_or_envelope, protocol_hint, expected_device_ids,
request_metadata}`. `expected_device_ids` carries the union of
`IDeviceDirectory.lookup_active(p.id) for p in recipients` so a
server-side `IBodyCodec` (e.g. `SignalEnvelopeValidator`) can reject
envelopes addressed to unknown devices.

`EncodedBody` is `{body: str | None, envelope: bytes | None, protocol: str}`
— exactly one of body/envelope set.

### 2.2 Lifecycle (file: `extensibility/lifecycle.py`)

```python
class IConversationPolicy(Protocol):
    """Multi-impl. All-must-allow. Default in meinchat = block-list
    respected. meinchat-plus registers `BothPeersHaveDeviceKeys` to veto
    e2e_v1 starts when any participant lacks a device key."""
    def may_start(self, initiator: User, peer: User, accepted_protocols: list[str]) -> None: ...


class IConversationCapabilities(Protocol):
    """Multi-impl. Union of returned sets is surfaced to the client.
    Default in meinchat = {'plain'}. meinchat-plus adds {'e2e_v1'}."""
    def for_conversation(self, conv: Conversation | None) -> set[str]: ...
```

### 2.3 Identity (file: `extensibility/identity.py`)

```python
class IDeviceDirectory(Protocol):
    """Single-impl. meinchat's default = NullDeviceDirectory:
        lookup_active(...) -> []
        has_any(...) -> False
        register(...) -> raise DirectoryNotEnabledError
    meinchat-plus replaces with `UserDeviceKeyDirectory` backed by
    `meinchat_plus_user_device_key`."""
    def register(self, user_id: UUID, pubkey: bytes, alg: str, label: str | None) -> Device: ...
    def lookup_active(self, user_id: UUID) -> list[Device]: ...
    def revoke(self, device_id: UUID) -> None: ...
    def has_any(self, user_id: UUID) -> bool: ...
```

### 2.4 Retention (file: `extensibility/retention.py`)

```python
class IRetentionPolicy(Protocol):
    """Single-impl. Default `ConfigRetentionPolicy` reads days from
    meinchat's config_store and prunes by `sent_at`. meinchat-plus
    replaces it with `E2eAwareRetentionPolicy` that ALSO exempts E2E
    rows whose `delivered_to_all_addressed_devices_at IS NULL` (so
    async-first-message delivery via prekey bundles survives the prune
    until the recipient comes online)."""
    def messages_keep_days(self) -> int: ...
    def attachments_keep_days(self) -> int: ...
    def should_prune(self, message: Message, now: datetime) -> bool: ...
```

### 2.5 Resolver helpers (file: `extensibility/registry.py`)

```python
def resolve_first(port_cls: type[T]) -> T:
    """Single-impl ports — last-write-wins, falls back to the default."""

def resolve_all(port_cls: type[T]) -> list[T]:
    """Multi-impl ports — chronological registration order."""

def register(port_cls: type[T], impl: T) -> None:
    """Plugin-side registration. Idempotent on same impl identity."""

def unregister(port_cls: type[T], impl: T) -> None:
    """Plugin-on-disable counterpart of register. Restores defaults
    cleanly so meinchat-alone behaviour returns on plugin disable."""

def reset_for_tests(port_cls: type[T] | None = None) -> None:
    """Test teardown — wipes the in-memory registry for one port or all."""
```

One file, ~60 LOC. Used by every port; no duplication across ports
(matches the existing `paymentDataContributors` / `checkoutPaymentMethods` shape).

### 2.6 Ports we explicitly did NOT extract (overengineering check)

| Port (in the earlier draft) | Why dropped |
|---|---|
| `IMessageValidator` | One default impl (length + non-empty), no second consumer in S28.3b. Stays inline in `MessageService._validate(...)`. |
| `IMessagePersister` | One impl (SQLAlchemy repo). The message-row write is not a meaningful seam — meinchat-plus stores the envelope on the same row. |
| `IBroadcaster` | One impl (`SseBroadcaster`). "Future push notifications" is speculative; defer until that plugin exists. |
| `IConversationFactory` | `start_or_get` has no replacement on the horizon; not a meaningful seam. |
| `INotificationDispatcher` | Speculative; same reasoning as `IBroadcaster`. |
| `IRateLimitPolicy` | Already exists from S26 inside meinchat; no port name needed at this layer. |

If a real second consumer for any appears, add the port then. Cost of
an abstraction with one impl is overhead.

## 3. Schema changes

Single Alembic migration in `plugins/meinchat/migrations/versions/`:

```sql
ALTER TABLE message
    ADD COLUMN envelope BYTEA NULL,
    ADD COLUMN protocol VARCHAR(32) NOT NULL DEFAULT 'plain',
    ADD COLUMN delivered_to_all_addressed_devices_at TIMESTAMPTZ NULL;

ALTER TABLE conversation
    ADD COLUMN protocol VARCHAR(32) NOT NULL DEFAULT 'plain',
    ADD COLUMN capabilities JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Drop body NOT NULL so ciphertext rows can have body IS NULL.
-- (Earlier draft used body = '' as a workaround — uglier, wastes a byte
-- per ciphertext row, and broke the >0-length CHECK if one existed.)
ALTER TABLE message ALTER COLUMN body DROP NOT NULL;

-- Replace the body-length check with a protocol-gated one + invariant
-- "exactly one of body / envelope is populated, matching the protocol".
ALTER TABLE message DROP CONSTRAINT IF EXISTS ck_message_body_len;
ALTER TABLE message ADD CONSTRAINT ck_message_body_len
    CHECK (protocol != 'plain' OR (body IS NOT NULL AND length(body) <= 4000));
ALTER TABLE message ADD CONSTRAINT ck_message_body_or_envelope
    CHECK ((protocol = 'plain' AND body IS NOT NULL AND envelope IS NULL)
        OR (protocol != 'plain' AND body IS NULL AND envelope IS NOT NULL));

-- Schema-pin the protocol on a conversation row: once an e2e_v1
-- conversation, always an e2e_v1 conversation. Closes the operator
-- downgrade attack at the storage layer (the route already refuses
-- to set conversation.protocol post-creation; this is defence-in-depth).
CREATE TRIGGER trg_conversation_protocol_immutable
    BEFORE UPDATE OF protocol ON conversation
    FOR EACH ROW WHEN (OLD.protocol IS DISTINCT FROM NEW.protocol)
    EXECUTE FUNCTION raise_protocol_immutable_violation();
-- (DDL for raise_protocol_immutable_violation() is in the same migration
--  file; the function RAISEs EXCEPTION 'protocol is immutable' so any
--  attempted downgrade aborts the txn.)

-- Backfill: existing rows are plaintext by definition.
-- (No update needed — DEFAULT handles new rows; existing rows pick up
-- the column NULL/default at ALTER time. `body NOT NULL → NULL allowed`
-- is a metadata-only change in PG; no rewrite.)
```

Backward-compatible: every today-row keeps `protocol = 'plain'`,
`envelope = NULL`, and `body` populated. The new columns are NULL or
default. `Message.to_dict()` extended to emit `protocol` + (for
ciphertext rows) `envelope` as base64. Plain rows continue to emit
`body` only — wire contract preserved for plain.

## 4. Refactoring `MessageService.send_text`

**Today** (rough shape):

```python
def send_text(self, sender, peer, body):
    self._validate_length(body)
    self._enforce_rate(...)
    row = Message(conversation_id=..., sender_id=sender.id, body=body, sent_at=now())
    self._repo.save(row)
    self._sse.broadcast(row)
    return row
```

**After 3a** (same external signature, only the seams that have a
concrete consumer become ports):

```python
def send_text(self, sender, peer, body_or_envelope, *, protocol_hint="plain"):
    self._enforce_rate(...)
    self._validate_length(body_or_envelope)                                       # inline — no port
    conv = self._conversation_service.start_or_get(sender, peer)                  # inline — no port
    for p in resolve_all(IConversationPolicy):
        p.may_start(sender, peer, accepted_protocols=[protocol_hint])             # raises on veto
    ctx = SendContext(sender=sender, recipients=[peer], conversation=conv,
                      body_or_envelope=body_or_envelope, protocol_hint=protocol_hint,
                      expected_device_ids=self._collect_device_ids(sender, peer),
                      request_metadata=...)
    encoded = resolve_first(IBodyCodec).encode(ctx)                               # default identity; meinchat-plus validates
    row = self._message_repo.save(Message.from_encoded(ctx, encoded))             # inline — no port
    self._sse.broadcast(row)                                                      # inline — no port
    for h in resolve_all(IPostSendHook):
        try: h.on_sent(row)
        except Exception as e: logger.error("post-send hook %s failed: %s", h, e)
    return row
```

Validator / persister / broadcaster / conversation-factory stay
**inline** — single impls today, no concrete second consumer in
S28.3b, so introducing a port is overhead. Adding the port later when
a real consumer appears is a small refactor (the inline call moves
behind a `resolve_first(...)`).

Defaults registered in `plugins/meinchat/__init__.py` `on_enable`:

```python
register(IBodyCodec, IdentityBodyCodec())
register(IConversationPolicy, BlockListPolicy(...))
register(IConversationCapabilities, PlainCapability())   # emits {"plain"}
register(IDeviceDirectory, NullDeviceDirectory())
register(IRetentionPolicy, ConfigRetentionPolicy(...))
# IPostSendHook starts empty; meinchat-plus adds MarkDeliveryAttempted.
```

All defaults preserve today's behaviour byte-for-byte. The "plugin-free
still works" oracle (§6.5) is the regression net.

## 5. New routes

### `GET /api/v1/messaging/capabilities[?me=true]` — **one endpoint, two shapes** (DRY)

The earlier draft had three overlapping endpoints (`/limits`,
`/capabilities`, `/me/capabilities`). Collapsed in this revision:

```
GET /api/v1/messaging/capabilities
→ { "server": ["plain", "e2e_v1"] }

GET /api/v1/messaging/capabilities?me=true
→ { "server": ["plain", "e2e_v1"], "me": ["plain"] }     # e.g. user has no device key
```

`server` is the union of `IConversationCapabilities.for_conversation(None)`
across all registered impls. `me` (only present with `?me=true`) is
the intersection with the caller's actual usability (e.g. `e2e_v1` needs
`IDeviceDirectory.has_any(caller.id)`).

### `GET /api/v1/messaging/limits` (unchanged from S28.0)

The earlier draft added `enabled_protocols` here. **Dropped** — the
capability surface lives on `/capabilities`. `/limits` stays
operator-knobs-only (retention windows + envelope size cap).

### `POST /api/v1/messaging/conversations` (extended)

Accepts optional `accepted_protocols: ["plain", "e2e_v1"]` from the
initiator. Server intersects with peer's capabilities. **The chosen
protocol is pinned on the conversation row** (immutable per the §3
trigger).

#### Negotiation-failure error contract

Closes critical-review §C6. Every failure mode has a deterministic
status + `code` so the client can render the right hint.

| Cause | HTTP | `code` | `hint` |
|---|---|---|---|
| peer has no active device key, initiator demands `e2e_v1` | 409 | `peer_has_no_device_keys` | `Ask @<peer> to enable secure chat on a device.` |
| `accepted_protocols ∩ peer_capabilities = ∅` | 409 | `protocol_negotiation_empty` | `No protocol accepted by both parties.` |
| `accepted_protocols` not a subset of server's enabled protocols | 400 | `protocol_not_enabled` | `Protocol '<p>' is not enabled on this instance.` |
| `accepted_protocols` omitted (back-compat) | 200 | n/a | server returns `protocol: "plain"` |

The meinchat-plus client MUST also verify the response `protocol` matches
what it demanded (downgrade fail-closed; S28.3b §3.6 / §4.5).

## 6. TDD plan

### 6.1 Registry-resolver specs (NEW) — `tests/unit/extensibility/test_registry.py` ≥ 10 specs

| # | Spec |
|---|---|
| 1 | `resolve_first` with no impls returns the registered default |
| 2 | `resolve_first` with two impls returns the last-registered (last-write-wins) |
| 3 | `resolve_first` with the default + one override returns the override |
| 4 | `resolve_all` with no impls returns `[]` |
| 5 | `resolve_all` preserves registration order |
| 6 | `reset_for_tests(port)` clears one port without touching others |
| 7 | `reset_for_tests()` clears every port |
| 8 | Re-registering the same instance is idempotent |
| 9 | Type-safety: `register(IBodyCodec, ConversationFactory())` raises a clear error |
| 10 | Registry isolation across test cases (fixture verifies a leak would fail) |

### 6.2 Default-impl specs

Each default's behaviour is locked in (so a future "improvement" can't silently change semantics):

- `test_identity_body_codec.py` ≥ 3 specs (encode → decode round-trip byte-equality, protocol=`"plain"`, envelope=`None`).
- `test_null_device_directory.py` ≥ 4 specs (`lookup_active=[]`, `has_any=False`, `register` raises, `revoke` raises).
- `test_plain_capability.py` ≥ 2 specs (set is `{"plain"}` for any conversation, idempotent).
- `test_block_list_policy.py` ≥ 3 specs (allowed pair passes, blocked pair raises, idempotent).
- `test_length_and_nonempty_validator.py` ≥ 4 specs (empty → veto, over-max → veto, at-max → pass, valid → pass).

### 6.3 `send_text` refactor — characterisation + contract

`tests/unit/services/test_message_service_send_text.py` (extended):

- **Characterisation block (red BEFORE the refactor, green AFTER):**
  - Same input → same output as today (compares the persisted row + the SSE event byte-for-byte).
  - Same exceptions for invalid input.
- **Contract block (new, green only AFTER):**
  - Each port is called exactly once in the expected order.
  - A throwing `IBroadcaster` is logged but doesn't fail the send.
  - A throwing `IPostSendHook` is logged but doesn't fail the send.
  - A vetoing `IMessageValidator` aborts before persist.

### 6.4 Capability + conversation negotiation specs

`tests/unit/routes/test_capabilities_endpoint.py` ≥ 6 specs:

1. `/capabilities` → `["plain"]` with default registry.
2. Adding a fake `IConversationCapabilities` impl returning `{"foo"}` → `/capabilities` includes `"foo"`.
3. `/me/capabilities` is the user-scoped subset (today identical to server-scoped).
4. `/limits` includes `enabled_protocols` matching `/capabilities`.
5. `POST /conversations` with `accepted_protocols=["e2e_v1", "plain"]` and meinchat-alone → conv `protocol='plain'`, `capabilities=["plain"]`.
6. The conversation row's `protocol` + `capabilities` columns are populated correctly.

### 6.5 "Plugin-free still works" oracle (the critical guard)

`tests/integration/test_meinchat_alone.py` (NEW) — boots the app with
**no downstream plugins loaded** and runs the equivalent of a smoke
suite:

- Register two test users.
- User A picks a nickname.
- User A starts a conversation with user B.
- A sends 3 messages, B sends 2.
- Both query `/messages?conversation_id=...` and see the expected rows
  in order, with `body` populated, `envelope` null, `protocol='plain'`.
- `RetentionService.prune_messages(days_to_keep=0)` cleans them all.
- The full `tests/integration/test_meinchat_e2e.py` (existing) is
  re-imported and re-run in this no-plugins context.

The CI matrix gets a new job that runs **only** this file in an isolated
plugin set — guaranteed signal if anyone introduces a hard dependency
on a downstream plugin from meinchat itself.

### 6.6 Static-analysis rule

`tests/unit/test_no_downstream_imports.py` — greps `plugins/meinchat/`
for any import of `plugins.meinchat_plus.*` or
`plugins.meinchat_enterprise.*`. Fails the build on any hit.

## 7. Acceptance criteria

- The `bin/pre-commit-check.sh --plugin meinchat --full` quality gate
  passes including the new oracle.
- A second-pass run of meinchat's existing integration suite is green
  byte-for-byte.
- `grep -RE "from plugins\.(meinchat_plus|meinchat_enterprise)" plugins/meinchat/` returns nothing.
- `curl /api/v1/messaging/capabilities` → `{"capabilities": ["plain"]}`.
- `curl /api/v1/messaging/limits` → same as S28.0 + `"enabled_protocols": ["plain"]`.
- A new Alembic head applies cleanly on a fresh DB AND on a DB that
  has the pre-3a schema (verified by the migration matrix's existing
  up/down/up oracle).

## 8. Out of scope

- The Signal ratchet impl — that's S28.3b.
- Touching `vbwd-backend/vbwd/` (core). Everything stays inside the
  meinchat plugin.
- Refactoring `AttachmentService` — left for S28.4 (which mirrors the
  pipeline pattern on the attachment write/read path).
- Group chats (multi-recipient `SendContext.recipients` > 1 is *typed*
  for future use but no code path exercises it yet; first concrete
  consumer is a future Sender Keys layer).

## 9. Engineering-requirements check

- **TDD-first:** ≥ 30 new/extended specs land before the refactor body
  is written. Characterisation block proves byte-for-byte unchanged
  externals.
- **DevOps-first:** new oracle job in CI; migration validated up/down/up
  against the existing test schema, including the `body DROP NOT NULL`
  + immutable-protocol trigger.
- **SOLID — S:** each port has exactly one job; no fat interfaces.
- **SOLID — O:** new behaviour comes from registered impls. Adding
  meinchat-plus in S28.3b doesn't modify any meinchat file.
- **SOLID — L:** the identity body codec is a behaviour-preserving
  substitute of the real one (encode/decode round-trips). The null
  device directory honours the same contract (`lookup_active` returns
  a list, `has_any` returns a bool — same shape, just empty).
- **SOLID — I:** ports are narrow (4 methods max — `IDeviceDirectory`
  is the widest).
- **SOLID — D:** every collaborator is injected — service constructor
  args, not module-level lookups.
- **NO OVERENGINEERING — concrete corrections in this revision.**
  - **12 ports → 6.** Dropped `IMessageValidator`, `IMessagePersister`,
    `IBroadcaster`, `IConversationFactory`, `INotificationDispatcher`,
    `IRateLimitPolicy`. Each had a single default impl and no concrete
    S28.3b consumer — the abstraction cost was pure overhead.
  - **3 capability endpoints → 1.** `/limits` + `/capabilities` +
    `/me/capabilities` collapsed to `/limits` + `/capabilities[?me=true]`.
    No shape duplication.
  - **`send_text` keeps validator/persister/broadcaster inline.**
    Each has one impl today; introducing a `resolve_first(...)` for
    them adds overhead without buying extensibility. Add the port if
    and when a second consumer arrives.
  - **No `meinchat-enterprise` surface drafted.** Port surface is
    general enough to host it later without re-touching meinchat.
- **DRY — concrete corrections.**
  - **One resolver pair** (`resolve_first`/`resolve_all`) covers every
    port — no duplicated registration code per port.
  - **One `SendContext` dataclass** threads through the pipeline (was
    multiple per-port context types in earlier drafts).
  - **One `NoDeviceKeysError`** lives here in meinchat (the base) and
    is re-used by both `BothPeersHaveDeviceKeys` (S28.3b) and
    `SignalAttachmentCodec` (S28.4).
- **Liskov on the wire:** plain rows' JSON shape is unchanged
  (`body` present; `envelope`, `protocol`,
  `delivered_to_all_addressed_devices_at` are new optional fields).
- **Core agnostic:** confirmed by the static-analysis rule (§6.6).
