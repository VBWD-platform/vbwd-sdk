# S28.6 — iOS meinchat plugin update (cache, retention, capabilities — beta-RC safe)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. Sister slice of [S28.2](s28-2-client-local-cache.md)
for the iOS package, framed against the **beta-RC** state of the
`vbwd-ios/VBWD` host app (MARKETING_VERSION `1.0`, CURRENT_PROJECT_VERSION
`1`, currently in TestFlight). Every change in this slice is **additive
inside the existing `vbwd-ios-plugin-meinchat` package** — no host-app
shell changes, no `VBWDCore` SDK breaking changes, no new external
Swift dependencies.
**Depends on:** [S28.0](s28-0-config-and-limits-endpoint.md) (backend
`/messaging/limits` endpoint + config keys), [S28.3a](s28-3a-meinchat-extension-ports.md)
(backend `/messaging/capabilities[?me=true]` endpoint + error contract).
**Blocks:** [S28.7](s28-7-ios-meinchat-plus-plugin-plan.md) — the new
meinchat-plus iOS plugin reuses this slice's `MeinChatLimitsService`
+ `MessageCache` + capability discovery.

**Repo touched:** `vbwd-ios/VBWD/Packages/vbwd-ios-plugin-meinchat/` only.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY ·
Liskov · clean code · **NO OVERENGINEERING** —
[`_engineering_requirements.md`](_engineering_requirements.md).
**Gate:** `swift test` GREEN on the plugin package (`Packages/vbwd-ios-plugin-meinchat`);
`mcp__xcode-tools__BuildProject` GREEN on the host app; full UITest
suite GREEN against a local backend with S28.0 + S28.3a merged.

---

## 1. Goal

Bring the existing iOS meinchat plugin in line with what S28.0–S28.3a
expects on the wire:

1. **Capabilities discovery.** The plugin reads
   `GET /messaging/capabilities[?me=true]` on bootstrap + every 24 h
   and surfaces the result to its views. A `meinchat-plus`-aware UI
   (S28.7) can later read the same service.
2. **Local message cache** with 10-day TTL (or user-shortened),
   **at-rest encrypted** under a Keychain-stored symmetric key per the
   S28.2 contract.
3. **Retention settings row** in the existing meinchat settings tab —
   read-only "kept for N days on this device / M days on the server"
   plus a stepper to shorten the local TTL.
4. **No crypto code in this slice** — that's S28.7. This slice keeps
   meinchat-alone (plain) behaviour byte-for-byte unchanged so a
   beta-RC user who never enables `meinchat-plus` sees zero behavioural
   change beyond the cache-first paint.

**Beta-RC constraint** (drives the design):
- No host-shell change (`VBWD/`). The plugin's bundled
  `plugins.json` entry stays unchanged — this slice ships under the
  same `meinchat` package, version-bumped to `1.1.0`.
- No `VBWDCore` SDK API change. Everything new is **inside the plugin's
  own `Sources/MeinChatPlugin/`** tree.
- No new Swift package dependency. CoreData + CryptoKit + Keychain are
  Apple frameworks; no `LibSignalClient` here.
- All changes are gated behind a `featureFlag.meinchat.cacheV1` in the
  plugin's settings (default ON for fresh installs; default OFF for
  upgrades from `1.0` → flipped ON automatically after 7 days in the
  field without crashes, monitored in TestFlight).

## 2. Current state (proof of pain)

- `useMeinchatStore`'s iOS counterpart `MeinChatStore` holds in-memory
  `[Conversation.id: [ChatMessage]]`. Cold app launch refetches the
  entire history from the server every time — a 2-day server
  retention (S28.1) would make every "open the app after 3 days
  offline" feel empty even if the user once had 30 days of chat.
- `ConversationViewModel.load()` already (per S26 follow-up s35) has a
  `conversationId` seed path; the cache reads slot in cleanly there.
- `MeinChatPlugin.bootstrap()` already registers a `MeinChatService`
  with `PlatformSDK.create(store:)`; same hook can spawn the new
  `MeinChatLimitsService` + the cache.
- No `MeinChatLimitsService` exists today. iOS hard-codes a 4-week
  retention assumption inside `RetentionCache.swift` (placeholder).

## 3. Design

Three additive Swift modules + one settings row. Everything inside
`Packages/vbwd-ios-plugin-meinchat/Sources/MeinChatPlugin/`.

### 3.1 `Domain/MeinChatLimitsService.swift` (NEW)

```swift
public protocol MeinChatLimitsServiceProtocol: AnyObject {
    var current: MessagingLimits? { get }
    var serverCapabilities: [String] { get }
    var myCapabilities: [String] { get }
    func refresh() async throws -> MessagingLimits
}

public struct MessagingLimits: Codable, Equatable {
    public let messagesRetentionDaysServer: Int
    public let messagesRetentionDaysClientSuggested: Int
    public let attachmentsRetentionDaysServer: Int
    public let ciphertextMaxBytes: Int
}

public final class MeinChatLimitsService: MeinChatLimitsServiceProtocol {
    private let api: APIClient
    private let cacheTTL: TimeInterval = 24 * 60 * 60
    private(set) public var current: MessagingLimits?
    private(set) public var serverCapabilities: [String] = ["plain"]
    private(set) public var myCapabilities: [String] = ["plain"]
    private var lastFetchedAt: Date?

    public init(api: APIClient) { self.api = api }

    public func refresh() async throws -> MessagingLimits {
        async let limits: MessagingLimits = api.get("/messaging/limits")
        async let caps: CapabilitiesResponse = api.get("/messaging/capabilities?me=true")
        let (l, c) = try await (limits, caps)
        current = l
        serverCapabilities = c.server
        myCapabilities = c.me ?? c.server
        lastFetchedAt = Date()
        return l
    }
}
```

Lazy-refresh: callers ask for `current`; if `nil` or older than
`cacheTTL`, kick off a background refresh. Network failure preserves
the last-good value (no `current = nil` rollback).

### 3.2 `Domain/MessageCache.swift` (NEW — per S28.2 §3)

CoreData model `CachedMessage` with sealed payload column (full
schema in S28.2 §3.1). Key stored in Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. **No SQLCipher
dependency** (per S28.2 NO OVERENGINEERING corrections);
`NSPersistentStoreFileProtectionKey =
FileProtectionType.completeUntilFirstUserAuthentication` + sealed
payload column is enough.

```swift
public protocol MessageCacheProtocol {
    func upsert(_ rows: [ChatMessage]) async throws
    func list(conversationID: UUID, limit: Int?) async throws -> [ChatMessage]
    func remove(conversationID: UUID) async throws
    @discardableResult
    func evict(olderThan: Date) async throws -> Int
}

public final class CoreDataMessageCache: MessageCacheProtocol {
    private let key: SymmetricKey       // loaded from Keychain at bootstrap
    private let context: NSManagedObjectContext
    // ... seal/open via ChaChaPoly.seal(_:using:) per row
}
```

DI'd into `MeinChatStore` via `MeinChatPlugin.bootstrap()`; never
held in a module-global.

### 3.3 `Domain/ClientRetentionResolver.swift` (NEW — DRY helper)

One place that answers "what TTL should the eviction sweep use?":

```swift
public final class ClientRetentionResolver {
    private let limits: MeinChatLimitsServiceProtocol
    private let userDefaults: UserDefaults
    private let key = "meinchat.client_retention_days"

    public func currentTTLSeconds() -> TimeInterval {
        let serverSuggested = limits.current?.messagesRetentionDaysClientSuggested ?? 10
        let user = userDefaults.object(forKey: key) as? Int ?? serverSuggested
        let effective = min(user, serverSuggested)               // shorten-only
        return TimeInterval(effective) * 86_400
    }

    public func setUserSetting(_ days: Int) {
        let clamped = max(0, min(days, limits.current?.messagesRetentionDaysClientSuggested ?? 365))
        userDefaults.set(clamped, forKey: key)
    }
}
```

Read by both the background eviction sweep and the settings stepper.

### 3.4 Background eviction (`Background/CacheEvictionTask.swift`)

`BGTaskScheduler` registers `vbwd.meinchat.cache-evict` to run at app
launch (best-effort) + every 24 h while resident. Calls
`cache.evict(olderThan: Date().addingTimeInterval(-resolver.currentTTLSeconds()))`.

### 3.5 `Views/ConversationViewModel.swift` (EDIT — cache-first paint)

```swift
public func load() async {
    isLoading = true; errorMessage = nil
    do {
        if let id = conversationID,
           let cached = try? await cache?.list(conversationID: id, limit: nil),
           !cached.isEmpty {
            messages = cached                                   // paint instantly
            isLoading = false                                   // remove spinner
        }
        let resolved = try await resolveConvID()
        let fresh = try await service.fetchMessages(convID: resolved, before: nil, limit: 50)
        messages = mergeByID(messages, fresh.reversed())        // server is canon
        try? await cache?.upsert(fresh)
        try? await service.markRead(convID: resolved)
        startPolling()
        isLoading = false
    } catch { /* unchanged error path */ }
}
```

Cache is optional via `init(... cache: MessageCacheProtocol? = nil)` —
a unit test can inject `nil` to exercise the no-cache path (Liskov).

### 3.6 Settings row (`Views/MeinChatRetentionSection.swift`)

Reuse the existing meinchat settings tab pattern. Two visible
controls:

> *"Chats are kept on the server for **2 days** and on this device for
> **N days**."*
>
> [Stepper: 0 … server_suggested] **N days**

Stepper writes through `ClientRetentionResolver.setUserSetting(_:)`.

### 3.7 Delivery + read receipts UI (`Views/ChatBubbleReceipts.swift`)

The message bubble for **outgoing** messages (sender = current user)
renders **0 / 1 / 2 small dots** in the bottom-right corner —
WhatsApp single-tick / double-tick style. This UI works for plain
conversations (this sprint's scope) **and** is reused unchanged by
S28.7 for e2e_v1 conversations — the data model is
protocol-agnostic (the receipt fields live on the `message` row, see
§3.7.1 below).

Visual spec:

```
┌─────────────────────────────────────────┐
│  Hey, are you coming tonight?           │
│                                  • •    │  ← 2 dots = read by recipient
└─────────────────────────────────────────┘    1 dot  = delivered to device
                                               0 dots = sent only to server
```

- Dot diameter: **5 pt**; 2 pt spacing between dots.
- Colour: `theme.accent` at 60 % opacity (subtle, doesn't compete
  with the body text).
- Position: 6 pt from the bubble's right edge, 4 pt from the bottom.
- **Only on outgoing messages.** Incoming messages never carry
  receipts (the receiver doesn't need to be told their own state).

State semantics:

| `delivered_at` | `read_at` | dots | meaning |
|---|---|---|---|
| NULL | NULL | (none) | Server accepted; recipient hasn't fetched yet. Transient. |
| not NULL | NULL | • | Recipient's client fetched the message via `GET /messages`. |
| not NULL | not NULL | • • | Recipient opened the conversation and the message scrolled into view (their client called `POST /messages/<id>/read`). |
| NULL | not NULL | — | Impossible: server-side CHECK `read_at IS NULL OR delivered_at IS NOT NULL`. |

When the local user opens a conversation and a message scrolls into
view, the iOS client `POST /messaging/messages/<message_id>/read` to
mark it as read. **Idempotent** — repeat calls on the same
`(message_id, user_id)` are no-ops after the first.

### 3.7.1 Backend prerequisite

The receipt UI requires two `message`-table columns + one new route
on the backend. These are added to
**[S28.3a](s28-3a-meinchat-extension-ports.md)** as an additive
schema concession + two routes:

```sql
ALTER TABLE message
    ADD COLUMN delivered_at TIMESTAMPTZ NULL,
    ADD COLUMN read_at      TIMESTAMPTZ NULL;
ALTER TABLE message ADD CONSTRAINT ck_message_read_implies_delivered
    CHECK (read_at IS NULL OR delivered_at IS NOT NULL);
```

Plus:
- `GET /api/v1/messaging/conversations/<conv>/messages` writes
  `delivered_at = now()` on every returned row where the caller is
  the recipient AND `delivered_at IS NULL`.
- `POST /api/v1/messaging/messages/<msg_id>/read` writes
  `read_at = now()` for the calling user (idempotent).

For e2e_v1 conversations, the same `message`-level columns are used.
S28.3b's `meinchat_plus_message_delivery` table (per-device fetched_at)
is independent: it answers "is this row prune-eligible?" not
"should the UI show a dot?". One concern, one home (DRY).

### 3.7.2 SwiftUI implementation

`Views/ChatBubbleReceipts.swift` (the spec for the shared component;
S28.7 imports it unchanged):

```swift
struct ChatBubbleReceipts: View {
    let deliveredAt: Date?
    let readAt: Date?

    var dotCount: Int {
        if readAt != nil { return 2 }
        if deliveredAt != nil { return 1 }
        return 0
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(theme.accent.opacity(0.6))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch dotCount {
        case 2: return "Read by recipient"
        case 1: return "Delivered"
        default: return "Sent"
        }
    }
}
```

`ChatMessageBubble` (existing) gains a trailing-bottom-right overlay
of `ChatBubbleReceipts` only when `message.senderID == currentUserID`.

### 3.7.3 Marking as read — `ConversationViewModel`

When a message becomes visible in the scroll view, the VM debounces
and posts `POST /messages/<id>/read` after the message has been
on-screen for ≥ 250 ms (so a rapid scroll-past doesn't fire). Uses
`onAppear` on the `ChatMessageBubble` + a `Task.detached` timer.

### 3.7.4 Web (fe-user) mirror

The same UI lands in
`vbwd-fe-user/plugins/meinchat/src/components/MessageBubble.vue` —
coordinated edit alongside this sprint, scoped under
**[S28.2](s28-2-client-local-cache.md)**'s fe-user plugin tree (same
package, same cache subsystem). One CSS class `.message-receipts`,
two `<span class="dot">` elements when `deliveredAt` / `readAt`
cross their thresholds.

### 3.8 NO OVERENGINEERING — what we DID NOT add

- **No new `VBWDCore` SDK port** for "limits service" or "message
  cache". These are meinchat-plugin-internal concerns; surfacing them
  to the SDK would lock in an abstraction that other plugins don't
  need.
- **No reactive `MeinChatLimitsService.publisher`.** Callers ask for
  `current`; the settings view re-reads on appear. Cuts a Combine
  surface that nothing else uses.
- **No SQLCipher.** NSFileProtection + sealed payload is enough; a
  SQLCipher dependency would inflate the binary and the audit surface
  for marginal benefit.
- **No new `PlatformSDK` extension point.** S28.7's meinchat-plus
  plugin extends meinchat via existing SDK seams (store registration,
  view overrides) — no new SDK API.
- **No re-architecture of `MeinChatStore`.** Cache is a sidecar, not
  a replacement.

## 4. TDD plan

`Packages/vbwd-ios-plugin-meinchat/Tests/MeinChatPluginTests/`:

### 4.1 `MeinChatLimitsServiceTests.swift` (NEW, ≥ 5 specs)

1. `test_refresh_returns_documented_fields` — mocked URLProtocol
   returns the four limits + two capability fields → `current` is
   populated.
2. `test_refresh_within_ttl_does_not_refetch` — calling twice within
   24 h triggers 1 URLProtocol hit.
3. `test_expired_ttl_refetches` — advance the clock past 24 h → 2 hits.
4. `test_failure_preserves_last_good` — first refresh succeeds; second
   fails; `current` still holds the first result.
5. `test_my_capabilities_falls_back_to_server` — response with no
   `me` field → `myCapabilities == serverCapabilities`.

### 4.2 `MessageCacheTests.swift` (NEW, ≥ 8 specs)

1. `test_upsert_then_list_roundtrip` — write 3 rows → read 3 rows in
   `sentAt` order.
2. `test_upsert_is_idempotent_on_same_id`.
3. `test_evict_olderThan_removes_only_matching_rows`.
4. `test_evict_returns_deleted_count`.
5. `test_remove_conversation_scoped_delete` (other convs untouched).
6. `test_raw_sqlite_file_does_not_contain_plaintext_marker` —
   write a row containing `"PLAIN_MARKER_FOR_S28_2"`, dump the SQLite
   file bytes, assert the marker is absent. Pins critical-review §C16.
7. `test_keychain_class_is_after_first_unlock_this_device_only` —
   query Keychain attributes; assert the class.
8. `test_corrupt_payload_skips_row_does_not_crash_app` — synthesise an
   unsealed payload column → list returns the other rows + logs the
   error (Liskov: cache is best-effort, not load-bearing).

### 4.3 `ClientRetentionResolverTests.swift` (NEW, ≥ 4 specs)

1. `test_defaults_to_server_suggested_when_user_unset`.
2. `test_user_setting_overrides_when_smaller`.
3. `test_user_setting_clamps_to_server_suggested_when_larger`.
4. `test_zero_days_yields_zero_seconds`.

### 4.4 `ConversationViewModelCacheTests.swift` (EXTEND, ≥ 3 specs)

1. Cached rows paint before the server response (network throttled).
2. Server rows merge by id; duplicates not duplicated.
3. After a server fetch, the cache is upserted with the server rows.

### 4.5 `MeinChatRetentionSectionTests.swift` (NEW, ≥ 2 specs)

1. Stepper `max` is bound to the server-suggested value.
2. Setting a value > server-suggested is clamped (UI rejects + the
   resolver clamps defensively).

### 4.6 `ChatBubbleReceiptsTests.swift` (NEW, ≥ 5 specs)

1. `test_zero_dots_when_neither_set` — `deliveredAt == nil`,
   `readAt == nil` → no dots rendered.
2. `test_one_dot_when_delivered_not_read` → one dot.
3. `test_two_dots_when_read` → two dots (regardless of
   `deliveredAt` — schema CHECK guarantees ordering).
4. `test_no_dots_on_incoming_messages` — receipts render only on
   outgoing bubbles (`message.senderID == currentUserID`).
5. `test_mark_read_debounce_250ms` — visible-for-<250ms scroll-past
   doesn't POST; ≥ 250 ms triggers exactly one POST per message per
   VM lifetime.

## 5. Acceptance

- `swift test` GREEN on `Packages/vbwd-ios-plugin-meinchat`.
- `mcp__xcode-tools__BuildProject` GREEN on the host app —
  signals beta-RC stability (no breaking API change to `VBWDCore`).
- Open the chat screen on a populated conversation, kill the app,
  reopen → all messages visible *before* the spinner clears (cache
  paint).
- `xcrun simctl get_app_container … data` dump of the SQLite file
  does **not** contain the plaintext body of any cached row (manual
  smoke + spec #6 above).
- Keychain item for the cache key has
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Settings → Meinchat → Retention shows live values from the
  backend; stepper clamps to the server-suggested value.
- A clean install with the backend offline still launches the chat
  surface (best-effort cache; no hard dependency on
  `/messaging/limits`).
- **Receipt UI live check (plain conversation):**
  - Send a message from device A to device B (different user) →
    bubble on A shows zero dots until B's client fetches; one dot
    after fetch; two dots after B's UI marks read.
  - Receipt dots are NEVER rendered on incoming bubbles.
  - `POST /messages/<id>/read` is idempotent — repeat calls in the
    same VM lifetime do not duplicate.

## 6. Out of scope

- **Any crypto.** That's [S28.7](s28-7-ios-meinchat-plus-plugin-plan.md).
- **Host-app shell changes.** Beta-RC freeze — every change is inside
  the plugin's package.
- **New `VBWDCore` SDK surface.** No new ports.
- **Cross-device cache sync.** Each device knows what it received.
- **Background pre-fetch of conversations the user didn't open.**
  Cache only stores what `ConversationViewModel.load()` saw.

## 7. Engineering-requirements check

- **TDD-first:** ≥ 22 new/extended specs land before the cache + limits
  service bodies are written. The "raw SQLite has no plaintext
  marker" spec pins the at-rest encryption guarantee.
- **DevOps-first:** `swift test` runs offline against
  `URLProtocol` mocks; UITests run online against a local backend
  built from S28.0 + S28.3a.
- **SOLID — S:** `MeinChatLimitsService` does one thing (fetch +
  cache the four limits + capabilities). `MessageCache` does one
  thing (persist + age out). `ClientRetentionResolver` does one
  thing (combine user + server settings).
- **SOLID — D (DI):** every collaborator (cache, KEK, retention
  resolver) is injected; no module-globals.
- **SOLID — L:** `MessageCacheProtocol` is substitutable — tests
  inject an in-memory fake; the no-cache path falls back cleanly.
- **NO OVERENGINEERING — concrete corrections.**
  - **No new `VBWDCore` SDK port** — these are plugin-internal
    concerns.
  - **No SQLCipher dependency** — NSFileProtection + sealed payload
    column is enough.
  - **No Combine `Publisher` for limits** — callers re-read on view
    appear; no realtime push.
  - **No `MessageCache` class hierarchy** — one protocol, one
    CoreData impl, one in-memory test impl.
- **DRY — concrete corrections.**
  - **Same Keychain key** powers the cache seal AND (when S28.7 lands)
    the meinchat-plus device-key wrap — one Keychain entry, two
    consumers. The key is derived once at bootstrap and reused.
  - **One `ClientRetentionResolver`** is the single home for "what
    TTL applies?" — both the background sweep and the settings UI
    call it.
- **Beta-RC safety:** every change is inside
  `Packages/vbwd-ios-plugin-meinchat/Sources/MeinChatPlugin/`. No
  host-shell change. No `VBWDCore` change. The `featureFlag.meinchat.cacheV1`
  gate lets TestFlight roll back cleanly if anything regresses.
- **Core agnostic:** the iOS host app shell is untouched.

---

## Anchor

Inherits the binding engineering requirements at
[`_engineering_requirements.md`](_engineering_requirements.md) (which
chains back to `../../20260525/sprints/_engineering-requirements.md`
and `../../20260519/sprints/_engineering-requirements.md`).
