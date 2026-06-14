# S68 — Backend: silent badge-update push on `markRead`

**Status:** PLANNED — 2026-06-12. Follow-up to [S66 ≡ S67.1](../../20260610/done/s66-backend-apns-push-notifications.md) (alert push on send). **Repo:** `vbwd-backend` — `vbwd/services/apns_client.py` (transport extension) + `plugins/meinchat/meinchat/services/` (the read-side hook). **Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](../../20260607/sprints/_engineering_requirements.md). **Quality gate:** `bin/pre-commit-check.sh --full` green on `vbwd-backend`.

---

## 1. Goal (user value)

After the user reads messages on **any** device (iOS, web, another iOS), the
app-icon badge on every other iOS device for that user updates within ~2 s
— **even when the app is suspended or killed**. Today the badge stays
stuck at the last-pushed number until the user opens the app, because
S66 only emits a push on `send_text`, not on `markRead`.

The exact target: home-screen icon badge always reflects `Σ unread_count`
for the user. Empty inbox → no red pill.

## 2. What is missing (grounded)

- `plugins/meinchat/meinchat/services/message_service.py:217` calls
  `_run_post_send_hooks(msg)` after a send → dispatches `PushEvent` through
  the core registry → meinchat push hook fires an alert payload with
  `aps.badge = Σ unread` (S66 §4.3). ✓
- **No symmetric hook on the read path.** `message_service.mark_read` and
  `message_service.mark_message_read` update the unread counters but emit
  nothing through the dispatcher registry. iOS has no way to learn the
  new total while the process is dead.
- `apns_client.send_bulk` always sends `apns-push-type: alert` — there's
  no `background` mode to emit silent badge-only payloads.

## 3. Architecture (extend the existing registry — no new seam)

| Concern | Owner | Agnostic? |
|---|---|---|
| `ApnsClient.send_bulk(push_type: Literal["alert","background"])` | core | yes |
| `PushEvent.kind: Literal["message","badge_only"]` (new field, default `"message"`) | core | yes |
| `push_dispatcher_registry.dispatch(event)` (unchanged) | core | yes |
| Translate `read → silent badge payload` | **plugins/meinchat** | gnostic |
| Fire dispatcher on `mark_read` / `mark_message_read` | **plugins/meinchat** | gnostic |

**Silent payload shape (gnostic — meinchat hook only):**

```json
{
  "aps": {
    "badge": <recipient_total_unread_after_read>,
    "content-available": 1
  }
}
```

- No `alert`, no `sound`, no `thread-id`. iOS surfaces nothing — only the
  icon badge updates.
- `apns-push-type: background`, `apns-priority: 5` (Apple requires `5` for
  background pushes), `apns-topic: <bundle_id>`.
- 410 → same revoke path as alert pushes (the hook owns revocation, S66
  §4.2 keeps that pattern).

### Why not a new dispatcher

`push_dispatcher_registry` already routes opaque `PushEvent`s. Adding a
`kind` field stays inside the same seam — no second registry, no new
import surface. The meinchat hook branches on `kind` to build either the
alert payload (existing) or the badge-only payload (new).

## 4. Files

### 4.1 Core

| Action | Path | Notes |
|---|---|---|
| edit | `vbwd-backend/vbwd/services/apns_client.py` | `send_bulk(payload, tokens, *, push_type="alert", priority=10)` — sets `apns-push-type` + `apns-priority`. Default unchanged → existing callers compile. |
| edit | `vbwd-backend/vbwd/services/push_dispatcher_registry.py` | `PushEvent.kind: Literal["message","badge_only"] = "message"`; back-compat default. |

### 4.2 meinchat consumer

| Action | Path | Notes |
|---|---|---|
| edit | `plugins/meinchat/meinchat/services/push_notification_hook.py` | Branch on `event.kind`: existing alert path for `"message"`, new silent-badge path for `"badge_only"`. Both share the unread-count query and the 410-revoke handling — extract a shared `_resolve_recipient_state(user_id)` helper if it costs <30 LOC. |
| edit | `plugins/meinchat/meinchat/services/message_service.py` | After `mark_read` / `mark_message_read` commit, dispatch `PushEvent(message=None, conversation=conv, recipient_user_id=caller_user_id, app="meinchat", kind="badge_only")`. The recipient is the reader themself — we're updating *their* other devices. Suppress on the originating device (same-token guard in the hook). |

### 4.3 Same-device suppression

A reader on iOS device A doesn't need to learn from APNs that they read —
device A already cleared its badge in-process. Two options to avoid the
loop:

- **(a)** Pass `originating_device_token: str | None` through `PushEvent`;
  the hook filters that token out before `send_bulk`. Cleanest.
- **(b)** Trust iOS to ignore a `content-available` push targeting an
  already-zero badge. Cheaper, but a tiny no-op push still wakes the
  device.

**Choose (a)** — narrow, accurate, no wasted radio time. Transport on
the wire: `POST /messaging/conversations/<id>/read?device_token=<hex>`
(query param — keeps the iOS `APIClient` protocol intact; no per-request
header API needed today). Backend reads `request.args.get("device_token")`
and scope-filters it out of the recipient broadcast. Web clients omit
the parameter → no suppression (correct — they have no APNs token).
**Already landed on the iOS side** in `MeinChatService.markRead` —
companion change is shipped, awaiting the backend to honour it.

## 5. TDD plan (RED first)

### 5.1 Core specs

- `tests/unit/vbwd/services/test_apns_client.py`
  - `test_send_bulk_alert_default_uses_apns_push_type_alert_and_priority_10`
  - `test_send_bulk_background_uses_apns_push_type_background_and_priority_5`
  - `test_send_bulk_background_payload_round_trip_byte_identical` —
    pin the silent shape so a future refactor can't accidentally add a
    `sound` / `alert` field.
- `tests/unit/vbwd/services/test_push_dispatcher_registry.py`
  - `test_push_event_defaults_kind_message_for_back_compat`
  - `test_push_event_kind_badge_only_round_trips_through_dispatch`

### 5.2 meinchat consumer

- `plugins/meinchat/tests/unit/services/test_push_notification_hook.py`
  - `test_badge_only_event_builds_silent_payload_with_zero_alert_keys`
  - `test_badge_only_event_uses_background_push_type_priority_5`
  - `test_badge_only_event_recomputes_badge_from_current_unread`
  - `test_badge_only_event_filters_originating_device_token` (option a)
- `plugins/meinchat/tests/unit/services/test_message_service.py`
  - `test_mark_read_dispatches_badge_only_push_event`
  - `test_mark_read_dispatch_passes_originating_token_header`
  - `test_mark_message_read_dispatches_badge_only_push_event`

### 5.3 Integration

- `plugins/meinchat/tests/integration/test_badge_silent_push_end_to_end.py`
  Extends the S66 integration test: register two device tokens for the
  same user, send a message from a peer (triggers alert push to both),
  call `markRead` with token-A's `X-VBWD-Device-Token`, and assert the
  fake APNs collector received **exactly one** background push — to
  token-B only, with `aps.badge = 0` and no `alert` / `sound` keys.

### 5.4 Quality gate

`bin/pre-commit-check.sh --full` green. Agnosticism / vocabulary oracles
must still pass (no `from plugins.*` import in `vbwd/`).

## 6. Acceptance

- A user with two iOS devices reads a conversation on device A. Within
  ~2 s, device B's home-screen icon badge updates to the recomputed
  total. The Lock screen + Notification Center show nothing.
- A user with one iOS device + one web tab reads on web. Within ~2 s,
  the iOS device's badge updates. (Web has no APNs token → no `X-VBWD-
  Device-Token` header → push fires to the iOS device, which is correct.)
- Same-device suppression: reading on iOS-A produces zero pushes to
  iOS-A (verified by collector token-filter).
- A 410 on the silent push revokes the token (same path as alert push).
- `bin/pre-commit-check.sh --full` green on `vbwd-backend`.

## 7. Out of scope (follow-ups)

- **Android / web push.** Same `PushEvent.kind` extension would work,
  but no consumers ship yet.
- **Mute / per-conversation DND** — silent badge update still fires for
  muted convs (the badge reflects unread regardless of mute), so this
  sprint is muting-orthogonal.
- **iOS NSE.** Out of scope — silent badge pushes don't need NSE.
- **Coalescing.** If a user smashes "mark all as read" across 50
  conversations in 2 s, we'd send 50 silent pushes per device. Apple's
  silent-push throttle absorbs this (≤2-3/hr per app per device on a
  fully-charged device, less on low battery). Add coalescing if telemetry
  shows it matters; defer for now.

## 8. iOS-side companion (already shipped, awaiting backend)

- `MeinChatService.markRead(convId:)` calls
  `DefaultNotificationsSDK.shared.currentTokenHex()` and, when non-nil,
  appends `?device_token=<hex>` to the `markRead` POST URL via
  `MeinChatEndpoints.markRead(convId:deviceToken:)`. Simulator builds
  (no token) omit the param — same-device suppression is unnecessary
  there anyway. New public actor method `currentTokenHex()` on
  `DefaultNotificationsSDK` exposes the buffered token.
- The web client makes **no** change — it has no APNs token and is
  correctly *not* suppressed.

## 9. Open decisions (resolve at kickoff)

1. **Coalesce per recipient per N seconds?** Default: NO (S66 telemetry
   shows median 1 read-event per chat-open; not a stampede).
2. **Background priority 5 vs 10?** Apple docs require 5 for
   `apns-push-type: background`. Locked.
3. **Same-user broadcast scope.** Silent pushes go to **all active iOS
   tokens for the reader's user_id, minus the originator**. Other users
   on the same conversation are unaffected (they didn't read; their
   badges shouldn't drop).
