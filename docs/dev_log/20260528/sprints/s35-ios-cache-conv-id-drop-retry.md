# S35 — iOS: cache conv_id from inbox, drop 429-retry loop

**Status:** PLANNED — 2026-05-28. Follow-up to [S26](s26-meinchat-rate-limits.md)
+ [S27](s27-lift-global-flask-limiter.md). After S26 the
`POST /api/v1/messaging/conversations` is idempotent + free for existing
chats, so the iOS pattern of POSTing on every `ConversationView` mount no
longer trips a 429 — but it's still a wasted request, and the 429-retry
loop at `ConversationViewModel.swift:61-66` becomes pointless code.
This sprint:
1. Plumbs the `conv.id` already known to `InboxView`'s row tap through to
   `ConversationView`, so the view-model boots with `conversationId` set
   and goes straight to `GET /messages/<conv_id>/messages`.
2. Drops the 429-retry exp-backoff loop in `ConversationViewModel.load()` —
   after S26 a 429 on this surface is a true server-side error, not a
   transient blip to retry.

**Track:** independent. **Repo:** `vbwd-ios` (Swift package
`vbwd-ios-plugin-meinchat`). **Engineering requirements (BINDING):**
TDD-first · NO OVERENGINEERING ·
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

---

## 1. Goal (user value)
Tapping an existing chat in the iOS inbox skips the
`POST /messaging/conversations` round-trip entirely — straight to
`GET /messages/<conv_id>/messages`. Net effect:
- One fewer HTTP request per chat-open (faster perceived nav).
- Zero impact on the `new_conversation` rate-limit counter (we never call
  the endpoint when we already have the `conv.id`).
- The "Find user → tap result" path (which DOES need to resolve a fresh
  `peer_nickname → conv.id`) is unchanged and still POSTs — that's correct,
  because that's the only path where a *brand-new* conversation may need
  creating.

## 2. Current flow (grounded)
- `InboxView.conversationRow(_:)`
  (`vbwd-ios/.../Views/InboxView.swift:105-113`) — on tap:
  - If `onOpenConversation` callback is wired, it gets both `nick` and
    `conv.id`.
  - Else (fallback) it sets `host.selectedRoute = "/meinchat/\(nick)"` —
    nickname only; `conv.id` dropped.
- `MeinChatRouter` (`Views/MeinChatRouter.swift:11-65`) parses the route
  and constructs a `ConversationView` for the nickname. It does NOT carry
  a `conversationId` even when one is known.
- `ConversationView` → `ConversationViewModel` init
  (`ConversationViewModel.swift:20-26`) accepts `conversationId: String?
  = nil` — so the entry point is already shaped to take it; nothing else
  passes it today.
- `ConversationViewModel.load()`
  (`ConversationViewModel.swift:35-75`):
  - Lines 40-44: retry loop with `2^attempt` second backoff,
    `Self.maxLoadRetries = 3`.
  - Lines 46-54: POSTs `openConversation` only when
    `conversationId == nil` — so when we DO have it, we skip already.
  - Lines 61-66: 429 retries with exp-backoff.

So the fix is two coordinated edits:
1. Make sure `conversationId` is **always** non-nil when the user opens an
   existing chat from the inbox.
2. Stop retrying on 429 (it's now a real error after S26, not a transient).

## 3. Design

### 3.1 Plumb `conv.id` through the route
Today the only generic transport from inbox tap → conversation view is
the string-based `host.selectedRoute = "/meinchat/<nick>"`. Two design
options:

- **(a) Extend the URL shape**: `/meinchat/<nick>?conv=<conv_id>`. The
  router parses the query, passes `conversationId` to the view.
  Lightweight, no new types, works with the existing string-route plumbing.
- **(b) Switch to a typed enum for routes**: define `case
  conversation(nickname: String, conversationId: String?)` and update the
  host's `selectedRoute` to take it. Cleaner long-term but touches more
  files outside this sprint's scope.

**Choose (a)** for NO OVERENGINEERING. The route grammar is already
URL-shaped — appending a query param is the smallest change that lets us
carry the extra bit.

### 3.2 Always set `conversationId` from the inbox
`InboxView.conversationRow` updates its `else` fallback to include the
`conv.id` in the URL:

```swift
host.selectedRoute = "/meinchat/\(nick)?conv=\(conv.id)"
```

The `onOpenConversation` callback path is unchanged — it already passes
both pieces.

### 3.3 Router parses the new query param
`MeinChatRouter` (`Views/MeinChatRouter.swift:21-65`) — extend the
nickname-resolver to also extract `conv` from the query, pass it as
`conversationId` to the `ConversationView` factory.

### 3.4 Drop the 429-retry loop in `ConversationViewModel.load()`
```swift
// before
for attempt in 0..<Self.maxLoadRetries {
    if attempt > 0 { try? await Task.sleep(...) }
    do { ... } catch let error as APIError {
        if case .http(let status, _) = error, status == 429 { continue }
        break
    }
}

// after
do { ... }
catch let error as APIError { lastError = error }
catch { lastError = error }
```

Plus delete `private static let maxLoadRetries = 3`.

After S26 the only way `openConversation` 429s is a real server-side
abuse cap; auto-retrying that just burns more slots without buying
anything. Show the error.

### 3.5 NO OVERENGINEERING
- **No URL-encoding library** — the `conv.id` is a UUID, no special chars.
- **No typed route enum** — too big for what's needed; the URL grammar is
  enough.
- **No fe-user mirror** — the web client (`vbwd-fe-user/.../ConversationView.vue:81-83`)
  has the same POST-on-mount pattern but its `useMeinchatStore.openConversation`
  is a single line and after S26 the POST is free; the iOS retry loop was
  the more harmful piece. A symmetric fe-user cleanup is its own sprint
  (S33 candidate; out of scope here).

## 4. TDD (RED first)

Swift XCTest in `vbwd-ios-plugin-meinchat/Tests/MeinChatPluginTests/`:

1. `test_conversation_view_model_with_seeded_id_does_not_call_openConversation`
   — `ConversationViewModel(peerNickname: "alice", service: mockService,
   conversationId: "<uuid>")`; `await load()` → assert
   `mockService.openConversationCalls == 0` and `fetchMessagesCalls == 1`
   with that `conv_id`.
2. `test_conversation_view_model_without_seeded_id_does_call_openConversation`
   — same setup but `conversationId: nil` → assert
   `mockService.openConversationCalls == 1`. (Regression guard for the
   FindUser path.)
3. `test_load_does_not_retry_on_429` — mock `openConversation` to throw
   `APIError.http(status: 429, ...)`; `await load()` → assert the call
   count is exactly **1**, not 3. errorMessage is populated.
4. `test_load_does_not_retry_on_other_http_errors` — symmetric (the old
   code already broke on non-429 — this just pins it).
5. `MeinChatRouter` route-parsing tests:
   - `test_router_parses_conv_query_param` — `/meinchat/alice?conv=<uuid>`
     → router yields `ConversationView(peerNickname: "alice",
     conversationId: <uuid>)`.
   - `test_router_handles_route_without_conv` —
     `/meinchat/alice` → `conversationId = nil` (FindUser path).

## 5. Files

| Action | Path |
| --- | --- |
| edit | `vbwd-ios/.../Views/ConversationViewModel.swift` — drop `maxLoadRetries`; drop the for-loop in `load()`; single-attempt try/catch. |
| edit | `vbwd-ios/.../Views/InboxView.swift` — `else` branch of `conversationRow` adds `?conv=<id>` to the route. |
| edit | `vbwd-ios/.../Views/MeinChatRouter.swift` — parse `conv` query param, pass it as `conversationId` to `ConversationView`. |
| new  | `vbwd-ios/.../Tests/MeinChatPluginTests/ConversationViewModelTests.swift` — §4 tests 1-4 (mock `MeinChatServiceProtocol`). |
| new  | `vbwd-ios/.../Tests/MeinChatPluginTests/MeinChatRouterTests.swift` — §4 tests 5-6. |

No backend change. No fe-user change. No new dependency.

## 6. Acceptance

- Tapping an existing chat from the iOS inbox issues **0** POSTs to
  `/api/v1/messaging/conversations` (verified via Charles / proxy log or
  the backend's S30 telemetry once that ships).
- Tapping "Find user → result" still POSTs once (FindUser path
  unchanged).
- `ConversationViewModel.load()` no longer retries on 429 — verified by
  test #3.
- All 6 new XCTest specs green; existing iOS-side tests still green.
- Manual repro: kill app on a long-running chat, relaunch, tap the inbox
  row 20× in a minute — no `new_conversation` quota slot consumed
  (backend counter for that user stays at zero).

## 7. Out of scope (follow-ups)

- **fe-user equivalent.** `vbwd-fe-user/plugins/meinchat/src/views/ConversationView.vue`
  has the same POST-on-mount pattern. After S26 the cost is one wasted
  idempotent POST per chat-mount. Worth fixing, but its own sprint (S33
  candidate).
- **Typed route enum.** Migrate `host.selectedRoute: String?` to a typed
  `MeinChatRoute` enum. Cleaner than query-param URLs but a deeper
  refactor — defer until the route grammar grows past 2 cases.
- **macOS testing.** Mac Catalyst build inherits the same view-model;
  tested implicitly. A dedicated macOS UI test isn't worth the harness
  cost.
