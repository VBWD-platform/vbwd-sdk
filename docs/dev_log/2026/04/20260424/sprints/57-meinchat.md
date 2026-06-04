# Sprint 57 — **meinchat** (nickname + contacts + messaging + token transfer)

**Status:** IMPLEMENTED — 2026-04-29 (pending repo extraction + prod deploy — see [report 03](../reports/03-meinchat-completion.md))
**Date:** 2026-04-24
**Implemented:** 2026-04-29
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding for every deliverable.

**Repos touched (all NEW, all standalone per `feedback_plugins_always_in_own_repos.md`):**
- `vbwd-plugin-meinchat` — backend plugin bundle: nickname column + directory, contacts, conversations + messages + SSE stream, token transfer.
- `vbwd-fe-user-plugin-meinchat` — user dashboard: inbox, contacts (address book), conversation view, find-user dialog, token-transfer dialog, profile-settings nickname widget.
- `vbwd-fe-admin-plugin-meinchat` — admin moderation: conversation inspector, nickname ban, transfer audit log.

**No changes to** `vbwd-backend` core, `vbwd-fe-core`, `vbwd-fe-user`, `vbwd-fe-admin`. Core stays agnostic — meinchat rides on the existing `user`, `token_balance`, `event_bus`, and `IFileStorage` abstractions without patching core code.

---

## Goal

Ship one plugin bundle that turns anonymous-ish VBWD users into **addressable peers** with an **address book**, a **real-time chat** (text + images), and **peer-to-peer token transfer** — all behind a single dashboard entry `💬 Messages`.

A merchant installing **meinchat** onto a fresh CE gets:

1. Every user can set a unique nickname (slug) on their profile — *"I'm @alice, find me there."*
2. Every user has an **address book** — save peers by nickname with a private alias, note, and pin; `/dashboard/messages/contacts`.
3. Any authenticated user can search other users by nickname prefix, open a 1-on-1 conversation, and send text + images with sub-second delivery (SSE).
4. Inside a conversation, either party can open "Send tokens", move N tokens from their wallet to the other's atomically; the transfer renders inline as a system message.

At sprint end, a demo script walks two seeded users (`alice`, `bob`) through the full loop on a local instance **and** on the `main` demo instance at `vbwd.cc`.

---

## Scope in / scope out

**In scope (v1):**
- 1-on-1 conversations only (group chat is a later sprint).
- Image attachments only (PNG/JPG/WebP, ≤ 5 MB, single image per message). Server re-encodes to strip EXIF, caps dimension at 2048 px.
- Text body up to 4000 chars; linkification safe, no Markdown, no HTML.
- Instant delivery via Server-Sent Events; offline users get messages on next page load.
- Token transfer: positive integer amount, no fee, single sender → single recipient, atomic.
- Address book: personal, per-user, with alias + note + pin flag.

**Out of scope (deferred):**
- Group chats, channels, threads, reactions, typing indicators, presence beyond "last seen" derived from `last_message_at`.
- Voice / video / non-image attachments.
- Federation, cross-instance DMs.
- Blocklists beyond an admin `banned_for_messaging` flag on nickname.
- Token fees, transfer scheduling, multi-hop transfers.
- Web push / email notifications for new messages (own sprint).
- E2E encryption. Messages sit in plaintext in Postgres — documented, not hidden.
- Bulk contact import / CSV export.

---

## Core engineering requirements

Binding for every deliverable. Inlines `../../20260422/sprints/_engineering-requirements.md` — read that first. Method-specific TDD checkpoints below extend it.

### Method-specific TDD checkpoints

**Nickname subsystem:**
- Slug validator — 10+ edge cases: lowercase, length bounds (3–32), reserved words (`admin, system, root, me, api, support, vbwd, null`), unicode rejected, consecutive dashes rejected, leading digit rejected.
- Unique index collision → `NicknameTakenError`.
- Nickname changes are free and uncapped — no cooldown gate.
- Ban grace-period reclaim: a banned nickname becomes available for re-registration once `now() - banned_at > nickname_ban_grace_period_days` (config key, default 30). Cleanup happens lazily at the start of `PUT /me` if a taken slug has a stale ban, and via a daily cron.
- Search: prefix-only (`ali*` → `alice`), capped at 10 results, excludes caller, banned, and `search_hidden`.

**Contacts subsystem:**
- `add(owner, contact_user_id)` — duplicate → 409; self-add → 400; unknown nickname → 404.
- List order: `pinned DESC, lower(coalesce(alias, nickname)) ASC`.
- Deleting a contact does **not** delete the conversation; conversation row persists so history stays accessible.

**Messaging subsystem:**
- Conversation-pair uniqueness — `start_or_get(a, b)` and `start_or_get(b, a)` resolve to the same row.
- Send-message snapshots the sender's nickname (so a later rename doesn't break old threads).
- Attachment upload: reject > 5 MB, reject non-image MIME, strip EXIF, produce a 256 px thumbnail; original + thumb both stored via `IFileStorage`.
- SSE stream: emits `heartbeat` every 20 s, `message` on new message to either participant, `read` on read receipt, `token_transfer` on system message. Disconnect on auth-token expiry.
- Rate limiter: 31st message in one minute → `429 MessageRateLimit`.
- Message delete is hard-delete on both sides: the row is removed, its `IFileStorage` attachment (original + thumb) is purged in the same transaction, and the recipient's UI loses the bubble on the next `message_deleted` SSE event.

**Token-transfer subsystem:**
- Insufficient balance → `InsufficientTokensError`, no rows mutated.
- Concurrent `A→B 10` and `A→C 10` when A has 15 — exactly one succeeds, the other raises (covered by a pytest + db row-lock integration test spinning two threads).
- Self-transfer (`sender == recipient`) → `ValueError`.
- Amount must be positive integer; floats, zero, and negatives → `ValueError`.
- Success path: row persisted + `token_service.deduct` + `token_service.credit` + `TokenTransferredEvent` emitted, all in one DB transaction.

---

## Architecture

Single backend plugin `vbwd-plugin-meinchat` with four cohesive subsystems. Layout follows `feedback_plugin_source_dir.md` — `meinchat/meinchat/` is the code dir.

```
vbwd-plugin-meinchat/
├── meinchat/__init__.py                 # MeinchatPlugin(BasePlugin) class lives here
├── meinchat/meinchat/
│   ├── models/
│   │   ├── user_nickname.py
│   │   ├── user_contact.py
│   │   ├── conversation.py
│   │   ├── message.py
│   │   └── token_transfer.py
│   ├── repositories/
│   │   ├── nickname_repository.py
│   │   ├── contact_repository.py
│   │   ├── conversation_repository.py
│   │   ├── message_repository.py
│   │   └── token_transfer_repository.py
│   ├── services/
│   │   ├── slug_validator.py
│   │   ├── nickname_service.py
│   │   ├── contact_service.py
│   │   ├── conversation_service.py       # pair uniqueness, start_or_get
│   │   ├── message_service.py            # send, read, paginate
│   │   ├── attachment_service.py         # Pillow sniff + re-encode + thumb
│   │   ├── sse_service.py                # subscribe / publish bridge over event_bus
│   │   └── token_transfer_service.py     # row-lock, deduct, credit, emit
│   ├── routes/
│   │   ├── nickname.py                   # /api/v1/nickname/*
│   │   ├── contacts.py                   # /api/v1/contacts/*
│   │   ├── messaging.py                  # /api/v1/messaging/*
│   │   └── token_transfer.py             # /api/v1/token-transfer/*
│   └── events.py                         # NicknameSetEvent, MessageSentEvent, …
├── alembic/versions/
│   ├── 20260424_1000_meinchat_nickname.py
│   ├── 20260424_1005_meinchat_contact.py
│   ├── 20260424_1010_meinchat_conversation_message.py
│   └── 20260424_1015_meinchat_token_transfer.py
├── tests/unit/                            # MagicMock collaborators, no DB
├── tests/integration/                     # real db fixture
├── populate_db.py                         # idempotent demo data
├── plugins.json patch                     # enabled: true
└── config.json patch                      # default config
                                           #   rate limits, attachment caps,
                                           #   nickname_ban_grace_period_days: 30
```

Plugin class (per `MEMORY.md` template):

```python
class MeinchatPlugin(BasePlugin):
    @property
    def metadata(self):
        return PluginMetadata(name="meinchat", version="1.0.0", ...)

    def get_blueprint(self):
        from plugins.meinchat.meinchat.routes import meinchat_bp
        return meinchat_bp

    def get_url_prefix(self):
        return ""   # four different route prefixes → absolute paths in routes

    def initialize(self, config=None):
        merged = {**DEFAULT_CONFIG, **(config or {})}
        super().initialize(merged)

    def on_enable(self): pass
    def on_disable(self): pass
```

### Models

```
user_nickname
─────────────
id              uuid       pk
user_id         uuid       fk → user.id  unique  ondelete=CASCADE
nickname        varchar(32) NOT NULL
nickname_ci     varchar(32) GENERATED STORED = lower(nickname)   (unique)
set_at          timestamptz
banned          boolean default false
banned_at       timestamptz nullable   ← when banned; used for grace-period reclaim
search_hidden   boolean default false
  unique btree (nickname_ci)
  btree (nickname_ci text_pattern_ops)   ← prefix search

user_contact
────────────
id               uuid       pk
owner_user_id    uuid       fk → user.id  ondelete=CASCADE
contact_user_id  uuid       fk → user.id  ondelete=CASCADE
alias            varchar(64)  nullable
note             varchar(500) nullable
pinned           boolean default false
added_at         timestamptz default now()
  unique (owner_user_id, contact_user_id)
  check  (owner_user_id <> contact_user_id)

conversation
────────────
id                    uuid       pk
participant_low_id    uuid       (LEAST of the two user ids)
participant_high_id   uuid       (GREATEST)
last_message_at       timestamptz
last_message_preview  varchar(120)
unread_low_count      integer    default 0
unread_high_count     integer    default 0
  unique (participant_low_id, participant_high_id)
  check  (participant_low_id <> participant_high_id)

message
───────
id                   uuid       pk
conversation_id      uuid       fk → conversation.id   ondelete=CASCADE
sender_id            uuid       fk → user.id
sender_nickname      varchar(32) (snapshot at send time)
body                 text       check(length(body) <= 4000)
attachment_url       varchar(512) nullable
attachment_thumb_url varchar(512) nullable
attachment_width_px  integer   nullable
attachment_height_px integer   nullable
sent_at              timestamptz default now()
delivered_at         timestamptz nullable
read_at              timestamptz nullable
system_kind          varchar(32) nullable   ("token_transfer" in v1)
  index (conversation_id, sent_at desc)

token_transfer
──────────────
id                 uuid       pk
sender_user_id     uuid       fk → user.id
recipient_user_id  uuid       fk → user.id
amount             integer    check (amount > 0)
note               varchar(200) nullable
executed_at        timestamptz default now()
  index (sender_user_id, executed_at desc)
  index (recipient_user_id, executed_at desc)
```

Four Alembic migrations (one per table), each idempotent (`_table_exists()` guard per the existing CMS pattern). No FKs across the four schemas; everything in-plugin.

### Nickname routes — `/api/v1/nickname`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET`   | `/me` | user | Current user's nickname (`null` if unset). |
| `PUT`   | `/me` | user | Set/change nickname. 7-day cooldown per change. |
| `GET`   | `/search?q=ali` | user | Prefix search, max 10 results, excludes banned + search_hidden + caller. |
| `GET`   | `/:nickname/card` | user | Public user card: `{nickname, display_name, joined_at, avatar_url}`. 404 if banned / hidden. |

Admin routes (same plugin, admin-prefixed):
| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/admin/meinchat/nicknames/:id/ban` | admin | Sets `banned = true`. |
| `POST` | `/api/v1/admin/meinchat/nicknames/:id/unban` | admin | Clears flag. |

Events emitted: `NicknameSetEvent(user_id, nickname, previous_nickname)`.

### Contacts routes — `/api/v1/contacts`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET`    | `/` | user | List — pinned first, alias-or-nickname alpha. |
| `POST`   | `/` | user | `{nickname, alias?, note?, pinned?}` — 404 unknown, 409 duplicate, 400 self. |
| `PATCH`  | `/:id` | user | Update alias / note / pinned. |
| `DELETE` | `/:id` | user | Remove (conversation untouched). |

### Messaging routes — `/api/v1/messaging`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET`    | `/conversations` | user | Paged list, newest first; includes peer nickname + unread count. |
| `POST`   | `/conversations` | user | `{peer_nickname}` → returns conversation (creates if absent). |
| `GET`    | `/conversations/:id/messages?before=<mid>` | user | 50 per page, cursor = `before`. |
| `POST`   | `/conversations/:id/messages` | user | `{body}` — text send. |
| `POST`   | `/conversations/:id/messages/attachment` | user | `multipart/form-data` — image, optional body. |
| `POST`   | `/conversations/:id/read` | user | Mark all unread-for-caller read. |
| `DELETE` | `/conversations/:id/messages/:mid` | user | Hard-delete (sender only); removes row + attachment files; emits `message_deleted` on both participants' streams. |
| `GET`    | `/stream?stream_token=<jwt>` | stream | Server-Sent Events. |
| `POST`   | `/stream/token` | user | Mint 60-min stream JWT (`aud=meinchat-stream`). |

**Rate limits (per authenticated user, Redis-backed):**
- `POST /messages`: 30/min.
- `POST /messages/attachment`: 6/hour.
- `POST /conversations` (new peer): 10/hour.
- `GET /nickname/search`: 30/min.

**SSE stream design (the "instant delivery" pipe):**

```
Browser ──EventSource──▶ GET /messaging/stream?stream_token=<JWT>
                                           │
                                           ▼
                     Flask route, long-lived response (text/event-stream)
                                           │ subscribe
                                           ▼
                            In-process event_bus (core)
                                           ▲
                                           │ publish
                                           │
  POST /messages ──▶ MessageService.save() ──▶ event_bus.publish("user:<recipient_id>", …)
```

1. Sender `POST /messages` → DB insert in a transaction.
2. On commit, `event_bus.publish(f"user:{recipient_id}", MessageSentPayload)`.
3. Every `/stream` connection listening for that `user_id` writes `data: {...}\n\n`.
4. Browser's `EventSource.onmessage` fires → store updates → Vue re-renders. Latency ≤ 100 ms.

Events on the wire: `message`, `message_deleted`, `read`, `token_transfer`, `heartbeat` (every 20 s).

Auth quirk: `EventSource` can't set headers. Flow = `POST /stream/token` (authenticated) → short-lived JWT → passed as `?stream_token=<jwt>`. `useMessagingStream` refreshes on 401 + reconnects.

Scale constraint documented up-front: in-process `event_bus` works while all users fit on one gunicorn worker. Multi-worker → swap the implementation to Redis pub/sub — same interface, ~20 lines. **Deferred to a later sprint per "no over-engineering".**

### Token-transfer routes — `/api/v1/token-transfer`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/` | user | `{to_nickname, amount, note}` → `{transfer_id, new_balance}`. |
| `GET` | `/history?direction=in|out|all` | user | Paged. |

Service flow (happy path): resolve nickname → reject self → open tx → `SELECT … FOR UPDATE` sender balance row → `token_service.deduct` → `token_service.credit` → insert `token_transfer` row → commit → `event_bus.publish(TokenTransferredEvent)`.

Event consumer wiring: `MessageService` subscribes to `TokenTransferredEvent`. On emit, inserts a `system_kind='token_transfer'` message into the (A, B) conversation (creating if absent) with body `{amount, note}` as JSON. This keeps the timeline unified — no second "events" view for users to consult.

---

## Frontend — `vbwd-fe-user-plugin-meinchat` (dashboard only)

### Dashboard placement

Same pattern as `llm-chat`: dashboard-only, single nav entry, no public-site footprint. All routes under `/dashboard/messages/*`.

| Route | Purpose |
|---|---|
| `/dashboard/messages` | Inbox — conversations list + Find-user. Default tab. |
| `/dashboard/messages/contacts` | Address book — saved contacts with alias / pin / note. |
| `/dashboard/messages/:nickname` | Conversation thread with that user. |
| `/dashboard/profile/nickname` | Nickname settings (profile subsection). |

Single nav entry via `userNavRegistry.register({ to: '/dashboard/messages', labelKey: 'nav.messages', badgeKey: 'meinchat.unreadTotal', testId: 'nav-messages' })`.

### Layout

Desktop (≥ 768 px): **two-pane** — left sidebar (tabbed: Inbox / Contacts) + right pane (conversation thread or empty-state). Same full-height column aesthetic as `ChatView.vue`.

Mobile: **one-pane router** — list view pushes `/messages/:nickname` on tap; browser back returns to list. No forced drawer.

```
┌────────────────────┬──────────────────────────────┐
│ [Inbox] [Contacts] │ @alice ▾       [💰 10] [⋮]   │
├────────────────────┼──────────────────────────────┤
│ @alice  · 12:04    │ Hey, got a sec?         12:04│
│ Hey, got a sec?    │                              │
│                    │               yeah — up?12:05│
│ @bob   · Yesterday │                              │
│ Thanks for tokens  │ [📷 image thumb]         12:07│
│                    │                              │
│ + Find user        │ ─ @alice sent 10 tokens ─    │
│                    ├──────────────────────────────┤
│                    │ [📎] Type a message…   [▶]   │
└────────────────────┴──────────────────────────────┘
```

### File layout

```
vbwd-fe-user-plugin-meinchat/
├── index.ts                              # plugin manifest
├── src/
│   ├── views/
│   │   ├── InboxView.vue                 # /dashboard/messages
│   │   ├── ContactsView.vue              # /dashboard/messages/contacts
│   │   ├── ConversationView.vue          # /dashboard/messages/:nickname
│   │   └── NicknameSettingsView.vue      # /dashboard/profile/nickname
│   ├── components/
│   │   ├── ConversationHeader.vue
│   │   ├── MessageBubble.vue             # text / image / system-token-transfer
│   │   ├── MessageComposer.vue           # text + attach + send
│   │   ├── InboxRow.vue
│   │   ├── ContactRow.vue
│   │   ├── AddContactDialog.vue
│   │   ├── FindUserDialog.vue
│   │   ├── TokenTransferDialog.vue
│   │   └── NicknameAvailabilityIndicator.vue
│   ├── composables/
│   │   ├── useMessagingStream.ts         # EventSource wrapper, auto-reconnect
│   │   ├── useNicknameSearch.ts          # debounced prefix search
│   │   └── useImageAttach.ts             # client-side preview + size check
│   ├── stores/
│   │   ├── useMeinchatStore.ts           # conversations, messages, unread counts
│   │   ├── useContactsStore.ts           # address book CRUD
│   │   └── useNicknameStore.ts           # my nickname + cooldown
│   └── api.ts                            # thin fetch wrappers (pattern from chat/api.ts)
├── locales/  {en,de,es,fr,ja,ru,th,zh}.json
└── tests/
    ├── unit/                              # Vitest — stores + composables
    └── e2e/                               # Playwright — inbox→contact→convo→image→token
```

### Address book implementation detail

**Store (`useContactsStore`):**
```ts
state:   { items: Contact[], loading: boolean }
actions: {
  fetch(),
  add(nickname, { alias?, note?, pinned? }),
  update(id, patch),
  remove(id),
  togglePin(id),
}
getters: {
  sorted,          // pinned first, then alpha by alias || nickname
  byNickname(nick) // lookup helper
}
```

Loaded on plugin `activate()` once (small per-user list, <1000 rows typical).

**`ContactsView.vue`:**

```
┌──────────────────────────────────────────┐
│ Contacts                    [+ Add contact]│
├──────────────────────────────────────────┤
│ 🔍 Filter contacts…                       │
├──────────────────────────────────────────┤
│ ⭐ Pinned                                  │
│   👤 @alice (Alice — mentor)              │
│      ► Message  ✎ Edit  🗑 Remove         │
│   👤 @carol                               │
├──────────────────────────────────────────┤
│ All                                       │
│   👤 @bob                                 │
│   👤 @dave                                │
└──────────────────────────────────────────┘
```

Row click → `router.push('/dashboard/messages/:nickname')`. On arrival, `ConversationView` calls `POST /conversations` which upserts and returns the conversation (no-op if it already exists).

**`AddContactDialog.vue`:**
1. Text input with 300 ms debounced `useNicknameSearch` — typeahead shows up to 10 matches.
2. Optional alias + note, optional pin checkbox.
3. Submit → `contactsStore.add(...)`; on success → toast + close; on 404 → inline "User not found"; on 409 → inline "Already in contacts".

**Distinguishing "save" vs "start chat":**
Inbox sidebar footer has a `+ Find user` button → opens `FindUserDialog.vue`. Same typeahead, but each result row has two actions: `[Start chat]` (pushes `/messages/:nick`) and `[Save contact]` (opens `AddContactDialog` prefilled). Contacts and conversations are orthogonal — you can save without chatting, chat without saving.

### Reuse from llm-chat

Template-level reuse (copied, not imported — plugin isolation):
- `ChatHeader` → `ConversationHeader` (peer avatar + nickname + `[💰 amount]` token button + `[⋮ more]`).
- `ChatMessage` → `MessageBubble` (new variants: text, image, system/token-transfer).
- `ChatInput` → `MessageComposer` (adds paperclip for image attach; same auto-resize, enter-to-send, max-length wiring).
- `.messages-area`, `empty-state`, `error-banner`, `typing-indicator` CSS patterns. Same `--vbwd-*` CSS variables for theme compatibility.

### Plugin manifest (named export, per `MEMORY.md`)

```ts
export const meinchatPlugin: IPlugin = {
  name: 'meinchat',
  version: '1.0.0',
  description: 'Nickname + contacts + instant messaging + token transfer',
  _active: false,

  install(sdk) {
    sdk.addRoute({ path: '/dashboard/messages',          name: 'meinchat-inbox',
                   component: () => import('./src/views/InboxView.vue'),
                   meta: { requiresAuth: true } });
    sdk.addRoute({ path: '/dashboard/messages/contacts', name: 'meinchat-contacts',
                   component: () => import('./src/views/ContactsView.vue'),
                   meta: { requiresAuth: true } });
    sdk.addRoute({ path: '/dashboard/messages/:nickname', name: 'meinchat-conversation',
                   component: () => import('./src/views/ConversationView.vue'),
                   meta: { requiresAuth: true }, props: true });
    sdk.addRoute({ path: '/dashboard/profile/nickname',  name: 'meinchat-nickname-settings',
                   component: () => import('./src/views/NicknameSettingsView.vue'),
                   meta: { requiresAuth: true } });
    sdk.addTranslations('en', en); /* …8 locales… */
  },

  activate() {
    this._active = true;
    userNavRegistry.register({
      pluginName: 'meinchat',
      to: '/dashboard/messages',
      labelKey: 'nav.messages',
      badgeKey: 'meinchat.unreadTotal',
      testId: 'nav-messages',
    });
  },

  deactivate() {
    this._active = false;
    userNavRegistry.unregister('meinchat');
  },
};
```

---

## Frontend — `vbwd-fe-admin-plugin-meinchat`

- Nav group "Meinchat" with children: Conversations, Transfers, Nicknames.
- `/admin/meinchat/conversations/:id` — read-only inspector with every message (soft-deleted included) for moderation.
- `/admin/meinchat/nicknames` — list with ban / unban, search-hidden toggle.
- `/admin/meinchat/transfers` — paged transfer log with `{sender, recipient, amount, executed_at}`.

Single fe-admin manifest; per `feedback_entity_navigation.md` every entity has a canonical detail route (no inline modals for conversation or transfer views).

---

## Demo data (populate script)

One `populate_db.py` in the backend plugin, idempotent:

1. Ensure demo users exist via `user_service.create_user` (not direct DB): `alice@example.com` / `AlicePass123@`, `bob@example.com` / `BobPass123@`.
2. Set nicknames `alice`, `bob`.
3. Add `@bob` to `@alice`'s contacts with alias "Bobby" and pin.
4. Credit 100 tokens to `alice` via `token_service.credit`.
5. Create a conversation `alice ↔ bob` with three seeded messages + one image attachment + one read receipt.
6. Run a `token_transfer` of 10 from alice to bob — verify the system message appears in the same conversation.

---

## Security posture

Explicit list — every item is a test + middleware + a comment explaining the why.

1. **Image upload:** MIME sniff (Pillow open), size cap 5 MB pre-decode, dimension cap 2048 px, EXIF stripped, re-encoded to WebP. Original never served.
2. **SSE auth:** short-lived `stream_token` (60 min), `aud=meinchat-stream`, revoked on logout (token list in Redis).
3. **Nickname enumeration:** prefix-only search, rate-limited 30/min, authenticated, excludes self + banned + `search_hidden`.
4. **XSS:** bodies rendered with Vue's `{{ }}` (auto-escaped). Linkification via `SafeLinkify.vue` — parses via `URL`, only emits `<a>` for `http(s):` schemes.
5. **CSRF:** JWT in `Authorization: Bearer` (VBWD convention) — no cookies → no CSRF surface.
6. **SQL injection:** SQLAlchemy parameterised only; prefix search uses `text_pattern_ops` index with `LIKE :prefix || '%'`.
7. **Rate limits:** per-user Redis counters; responses include `Retry-After`.
8. **Token transfer atomicity:** `SELECT … FOR UPDATE` on sender balance; single DB transaction covers deduct + credit + record.
9. **Self-ban:** admin ban endpoint returns 409 if admin tries to ban their own nickname.

---

## Observability

- Structured logs with `plugin=meinchat` label.
- Prometheus metrics (scraped by core `/metrics`):
  - `meinchat_messages_sent_total{kind="text|attachment|system"}`
  - `meinchat_sse_connections_gauge`
  - `meinchat_token_transfer_volume_total{direction="in|out"}`
  - `meinchat_token_transfer_failures_total{reason="insufficient_balance|self|rate_limit"}`

---

## Rollout plan

1. **Day 1-2:** Nickname subsystem — model, migration, validator, repo, service, routes, tests. fe-user `NicknameSettingsView` + store.
2. **Day 3:** Contacts subsystem — model, migration, repo, service, routes, tests. fe-user `useContactsStore` + `ContactsView` + `AddContactDialog`.
3. **Day 4-6:** Messaging backend — models, migrations, services (conversation, message, attachment, SSE), routes, rate limiter, tests. Integration-testable end-to-end via curl + `curl -N` for SSE.
4. **Day 7:** Token-transfer subsystem — model, service with row locks, routes, tests. Integration test for concurrent transfer.
5. **Day 8-10:** fe-user messaging views — `InboxView`, `ConversationView`, `MessageComposer`, attachment upload, `TokenTransferDialog`, `useMessagingStream`. Vitest + Playwright.
6. **Day 11:** fe-admin plugin — Conversation inspector, Nicknames list, Transfers audit.
7. **Day 12:** Demo instance enable — add `meinchat` to `main` instance's `backend-plugins.json`, `fe-user-plugins.json`, `fe-admin-plugins.json`. Deploy workflow → smoke-test alice↔bob loop on `vbwd.cc`.
8. **Day 13:** CI hardening per `feedback_ci_precommit_lessons.md` — all three plugin repos pass `pre-commit-check.sh --full`. Sprint retro.

---

## Definition of done (the gate)

1. All specs authored first, watched fail, now green. Backend plugin has ≥ 40 pytest cases covering the method-specific checkpoints (nickname, contacts, messaging, token-transfer).
2. `bin/pre-commit-check.sh --full` passes on every touched plugin repo — including the non-skippable gate lines (`bash -n`, mypy excluding tests, eslint project-wide, vitest using `plugins/<name>/` filter).
3. No rule in `_engineering-requirements.md` is violated. Specifically:
   - No `# noqa` / `# type: ignore` added without explicit approval.
   - No host-side `npm install` in bind-mounted `vbwd-fe-core`.
   - No raw SQL migrations.
   - All plugin code lives in its own repo — nothing pushed into `vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin`.
   - No temp branches left on any repo.
4. No deprecated code left behind. Any early-sprint scaffolding (temporary fixtures, mock gateways) is deleted.
5. Demo instance `main` on `vbwd.cc` boots with meinchat enabled. `alice@example.com` logs in on fe-user, opens `/dashboard/messages`, finds `@bob`, sends a text + image, transfers 10 tokens — Bob receives the message instantly (SSE verified via browser Network tab), the image renders, the token transfer appears as a system bubble. Admin can inspect the conversation via fe-admin at `/admin/meinchat/conversations/<id>`.

---

## Test plan summary

| Layer | Coverage |
|---|---|
| **Backend unit** | Slug validator edge cases, conversation-pair uniqueness helper, attachment MIME + size + EXIF, SSE token mint/verify, token-transfer service (happy path + 4 failure paths), contacts CRUD, rate limiter. |
| **Backend integration** | Migrations up/down idempotency, `SELECT FOR UPDATE` concurrent transfer, SSE end-to-end over pytest's `gevent` + a `requests` session, real `LocalFileStorage` round-trip for attachments, real Redis for rate limits. |
| **Frontend unit** | `useMeinchatStore` optimistic send + rollback, `useContactsStore` sort order + duplicate guard, `useMessagingStream` reconnect logic, `SafeLinkify` XSS round-trip, `TokenTransferDialog` amount validation. |
| **Frontend E2E** | Full alice↔bob loop (Playwright): login as alice, find bob, save as contact with alias "Bobby", send text, upload image, send 10 tokens, log out, log in as bob, verify message + image + transfer all visible with correct nickname + timestamp. |

---

## References

- `_engineering-requirements.md` — binding core standards.
- `MEMORY.md`:
  - Plugin Architecture Pattern (new `plugins/<name>/<name>/` dir).
  - Plugin Class Template.
  - Test Pattern (`_test_db_url()` suffix).
  - fe-user Plugin Export Convention (named exports, not default).
  - UX / Navigation Principle (detail views never inline modals).
- `feedback_plugins_always_in_own_repos.md` — one backend + two frontend plugins, all in standalone `vbwd-plugin-meinchat*` repos.
- `feedback_migrations_only.md` — schema changes through Alembic, not raw SQL.
- `feedback_no_noqa_without_permission.md` — no suppression comments; fix root causes.
- `project_fe_core_design_system.md` — all shared UI tokens via `var(--vbwd-*)`.
- `feedback_entity_navigation.md` — conversations, transfers, contacts each get canonical detail routes.

---

## Locked decisions (2026-04-24)

1. **Nickname change cost** — free, no cooldown, no token cost. The `last_changed_at` column does not exist; nothing gates a rename beyond slug validation + uniqueness.
2. **Token-transfer minimum** — any positive integer ≥ 1. Floor check is the `check (amount > 0)` DB constraint plus the service's `ValueError` on zero/negative/float.
3. **Attachment retention** — attachments are purged when the parent message is hard-deleted (one transaction: row delete + `IFileStorage.delete(original)` + `IFileStorage.delete(thumb)`). No TTL job, no conversation-delete sweep in v1.
4. **Message delete semantics** — hard delete on both sides. Sender's `DELETE /messages/:mid` removes the row; both participants' SSE streams emit `message_deleted`; bubbles disappear from both UIs. No "(deleted)" tombstone, no dual-menu "delete for me / for everyone".
5. **Banned nickname slug reclaim** — released after a grace period driven by plugin config `meinchat.nickname_ban_grace_period_days` (default 30). Implementation: `banned_at` timestamp on `user_nickname`; lazy check on `PUT /nickname/me` + a daily cron deletes rows where `banned=true AND now() - banned_at > interval '<N> days'`.
6. **Address-book scope** — per-user private. `user_contact.owner_user_id` scopes every row; no global or tenant-shared directory.
7. **Presence** — no live online indicator. Contact rows and conversation headers show "last seen" derived from `conversation.last_message_at` ("12 min ago"). Green-dot presence is a separate later sprint.

All seven were closed before the first commit; the spec rows above reflect them.
