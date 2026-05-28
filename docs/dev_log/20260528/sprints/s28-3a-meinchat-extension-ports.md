# S28.3a — meinchat extension ports + schema concessions + capability endpoints (refactor)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
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

## 2. The six ports

All in a new `plugins/meinchat/meinchat/extensibility/` directory.

### 2.1 Pipeline (file: `extensibility/pipeline.py`)

```python
class IMessageValidator(Protocol):
    """Pre-write check. All registered impls must pass (any may veto)."""
    def validate(self, ctx: SendContext) -> None: ...   # raise on failure


class IBodyCodec(Protocol):
    """Bidirectional transform — encode on send, decode on read.
    Single-impl; last-write-wins. Default in meinchat = identity."""
    def encode(self, ctx: SendContext) -> EncodedBody: ...
    def decode(self, row: Message, viewer_device: Device | None) -> str: ...


class IMessagePersister(Protocol):
    """Write a row. Single-impl. Default = SQLAlchemy through the existing repo."""
    def persist(self, ctx: SendContext, encoded: EncodedBody) -> Message: ...


class IBroadcaster(Protocol):
    """Push to live subscribers. Multi-impl, fan-out, error-tolerant.
    Default in meinchat = [SseBroadcaster]."""
    def broadcast(self, row: Message) -> None: ...


class IPostSendHook(Protocol):
    """After-the-fact side effects (audit, analytics, …). Multi-impl;
    a throwing hook is logged at error, never propagated."""
    def on_sent(self, row: Message) -> None: ...
```

`SendContext` is a frozen dataclass with `{sender, recipients, conversation, body_or_envelope, protocol_hint, request_metadata}`.
`EncodedBody` is `{body: str | None, envelope: bytes | None, protocol: str}` — exactly one of body/envelope set.

### 2.2 Lifecycle (file: `extensibility/lifecycle.py`)

```python
class IConversationFactory(Protocol):
    """Single-impl. Default = today's start-or-get."""
    def create_or_get(self, initiator: User, peer: User, accepted_protocols: list[str]) -> Conversation: ...


class IConversationPolicy(Protocol):
    """Multi-impl. All-must-allow. Default in meinchat = block-list respected."""
    def may_start(self, initiator: User, peer: User) -> None: ...   # raise on veto


class IConversationCapabilities(Protocol):
    """Multi-impl. Union of returned sets is surfaced to the client.
    Default in meinchat = {'plain'}."""
    def for_conversation(self, conv: Conversation) -> set[str]: ...
```

### 2.3 Identity (file: `extensibility/identity.py`)

```python
class IDeviceDirectory(Protocol):
    """Single-impl. meinchat's default = NullDeviceDirectory:
        lookup_active(...) -> []
        has_any(...) -> False
        register(...) -> raise DirectoryNotEnabledError
    meinchat-plus replaces with a real impl backed by user_device_key."""
    def register(self, user_id: UUID, pubkey: bytes, alg: str, label: str | None) -> Device: ...
    def lookup_active(self, user_id: UUID) -> list[Device]: ...
    def revoke(self, device_id: UUID) -> None: ...
    def has_any(self, user_id: UUID) -> bool: ...
```

### 2.4 Retention (file: `extensibility/retention.py`)

Already exists conceptually from S28.1 — formalised here as a port so
a downstream plugin (e.g. a future legal-hold extension) could
register its own override. **Default in meinchat reads from the config
keys S28.0 added**; that default stays.

```python
class IRetentionPolicy(Protocol):
    """Single-impl. Default reads from meinchat's config_store."""
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

def reset_for_tests(port_cls: type[T] | None = None) -> None:
    """Test teardown — wipes the in-memory registry for one port or all."""
```

One file, ~50 LOC. Used by every port, no duplication across ports
(matches the existing `paymentDataContributors` / `checkoutPaymentMethods` shape).

## 3. Schema changes

Single Alembic migration in `plugins/meinchat/migrations/versions/`:

```sql
ALTER TABLE message
    ADD COLUMN envelope BYTEA NULL,
    ADD COLUMN protocol VARCHAR(32) NOT NULL DEFAULT 'plain';

ALTER TABLE conversation
    ADD COLUMN protocol VARCHAR(32) NOT NULL DEFAULT 'plain',
    ADD COLUMN capabilities JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Preserve the today-existing TEXT length constraint for plain rows only;
-- ciphertext rows are allowed to exceed 4 000.
ALTER TABLE message DROP CONSTRAINT ck_message_body_len;
ALTER TABLE message ADD CONSTRAINT ck_message_body_len
    CHECK (protocol != 'plain' OR length(body) <= 4000);

-- Backfill: existing rows are plaintext by definition.
-- (No update needed — DEFAULT handles new rows; existing rows pick up the column NULL/default at ALTER time.)
```

Backward-compatible. Every today-row keeps `protocol = 'plain'` and
`envelope = NULL`; `body` semantics unchanged.

`Message.to_dict()` extended to emit `protocol` + (for ciphertext rows)
`envelope` as base64. Plain rows continue to emit `body` only — wire
contract preserved for plain.

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

**After 3a** (same external signature, internals via ports):

```python
def send_text(self, sender, peer, body):
    self._enforce_rate(...)                                      # unchanged — rate limit is a meinchat concern
    conv = resolve_first(IConversationFactory).create_or_get(sender, peer, accepted_protocols=["plain"])
    ctx = SendContext(sender=sender, recipients=[peer], conversation=conv,
                      body_or_envelope=body, protocol_hint=conv.protocol, request_metadata=...)
    for v in resolve_all(IMessageValidator):
        v.validate(ctx)                                          # raises on veto
    encoded = resolve_first(IBodyCodec).encode(ctx)
    row = resolve_first(IMessagePersister).persist(ctx, encoded)
    for b in resolve_all(IBroadcaster):
        try: b.broadcast(row)
        except Exception as e: logger.error("broadcast %s failed: %s", b, e)
    for h in resolve_all(IPostSendHook):
        try: h.on_sent(row)
        except Exception as e: logger.error("post-send hook %s failed: %s", h, e)
    return row
```

Defaults registered in `plugins/meinchat/__init__.py` `on_enable`:

```python
register(IBodyCodec, IdentityBodyCodec())
register(IMessagePersister, SqlAlchemyMessagePersister(...))
register(IBroadcaster, SseBroadcaster(...))
register(IConversationFactory, StartOrGetFactory(...))
# multi-impls default-empty: IMessageValidator, IConversationPolicy,
# IConversationCapabilities, IPostSendHook
register(IConversationCapabilities, PlainCapability())   # always emits {"plain"}
register(IMessageValidator, LengthAndNonEmptyValidator())
register(IConversationPolicy, BlockListPolicy(...))
register(IDeviceDirectory, NullDeviceDirectory())
register(IRetentionPolicy, ConfigRetentionPolicy(...))
```

All defaults preserve today's behaviour byte-for-byte.

## 5. New routes

### `GET /api/v1/messaging/capabilities`

Returns the union of `{IConversationCapabilities.for_conversation(...)}`
across **all registered impls**, with no conversation context (a "what
can this server installation do at all" query). Used by clients to
decide which onboarding flows to show.

```json
{ "capabilities": ["plain"] }
```

With meinchat-plus enabled, this becomes `["plain", "e2e_v1"]`.

### `GET /api/v1/messaging/me/capabilities`

Same shape but per-user — the subset of server capabilities that this
user can *actually use* right now (e.g. needs ≥ 1 registered device for
`e2e_v1`). With meinchat alone: `["plain"]`. With meinchat-plus + no
device key: `["plain"]`. With meinchat-plus + a device key: `["plain", "e2e_v1"]`.

### `GET /api/v1/messaging/limits` (extended)

Adds `enabled_protocols: [...]` to the response (was hardcoded `["plain"]`
in S28.0; now resolves from `IConversationCapabilities`).

### `POST /api/v1/messaging/conversations` (extended)

Accepts optional `accepted_protocols: ["plain", "e2e_v1"]` from the
initiator. Factory intersects with the peer's capabilities and stores
the negotiated `protocol` + `capabilities` on the conversation row.
With meinchat alone, peer's set is `{"plain"}` → intersection is `{"plain"}`.

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
  against the existing test schema.
- **SOLID — S:** each port has exactly one job; no fat interfaces.
- **SOLID — O:** new behaviour comes from registered impls. Adding
  meinchat-plus in S28.3b doesn't modify any meinchat file.
- **SOLID — L:** the identity body codec is a *behaviour-preserving*
  substitute of the real one (encode/decode round-trips). The null
  device directory honours the same contract (`lookup_active` returns
  a list, `has_any` returns a bool — same shape, just empty).
- **SOLID — I:** ports are narrow (4 methods max).
- **SOLID — D:** every collaborator is injected — service constructor
  args, not module-level lookups.
- **DRY:** one resolver pair (`resolve_first`/`resolve_all`) covers
  every port; one `SendContext` dataclass passed through the pipeline.
- **Liskov on the wire:** plain rows' JSON shape is unchanged
  (`body` present, `envelope` and `protocol` are new optional fields).
- **NO OVERENGINEERING:** zero ports added "just in case." Each one
  has a concrete consumer landing in S28.3b. No `meinchat-enterprise`
  surface invented.
- **Core agnostic:** confirmed by the static-analysis rule (§6.6).
