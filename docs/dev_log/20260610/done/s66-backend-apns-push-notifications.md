# S66 — Backend APNs push notifications for meinchat (+ meinchat-plus)

**Status:** 🟢 DONE on disk, gate-green — 2026-06-11 (see [report 05](../../20260611/reports/05-s66-s67-1-backend-apns-push.md)); not committed. The **backend half** of the notifications feature = **[S67.1 (BE)](s67-1-be-device-registration-and-push.md)** under the [S67 umbrella](s67-notifications-and-badges.md); **this file stays the canonical detailed backend design** (S66 ≡ S67.1 — implement once). iOS half: [S67.2 (iOS)](s67-ios-notifications-and-badges.md).
**Repo:** `vbwd-backend` (**core** `vbwd/` for the generic device-token
mechanism; **plugins/meinchat** for the consumer hook). **Engineering
requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov ·
clean code · NO OVERENGINEERING —
[`_engineering_requirements.md`](../../20260607/sprints/_engineering_requirements.md).
**Quality gate:** `bin/pre-commit-check.sh --full` green on `vbwd-backend`.

---

## 1. Goal (user value)

When user A sends a message to user B in meinchat (or meinchat-plus), user B's
iOS device receives an **APNs push notification** — visible on the Lock screen,
in Notification Center, and on the app icon (badge with the unread total).
Tapping it opens the conversation. Encrypted (`protocol=e2e_v1`) messages still
notify, but the payload carries only a generic body (`"🔒 New encrypted
message"`) — the server cannot decrypt.

## 2. What is missing (grounded)

- No `device_token` model, repository or route exists. `grep -rn "device_token"
  vbwd-backend/` is empty.
- `MessageService.send_text` (`plugins/meinchat/meinchat/services/message_service.py:213`)
  already calls `self._run_post_send_hooks(msg)` — the *seam* exists, but no
  push hook is registered.
- No APNs sender. No env vars. No `.p8` key plumbing. Pre-S66 the system is
  poll-only: iOS hits the inbox every 5 s while the app is in the foreground;
  backgrounded → nothing.

## 3. Architecture (mechanism in core, hook in plugin)

Same separation pattern S52 used for API keys: **mechanism in core, meaning in
plugin.**

| Concern | Owner | Agnostic? |
|---|---|---|
| `device_token` model (user_id, token, platform, bundle_id, app, last_seen_at) | core | yes — no domain fields |
| `DeviceTokenService.{register, unregister, find_by_user, mark_seen}` | core | yes |
| `POST /api/v1/devices/register`, `DELETE /api/v1/devices/<token>` | core | yes |
| `ApnsClient` (HTTP/2 + JWT) — opaque payload + recipient tokens | core | yes |
| `push_dispatcher_registry` (Kind-1 generic registry, S50 STAY column) | core | yes |
| Translate `Message → APNs payload` (`title/body/badge/conv_id/message_id`) | **plugins/meinchat** | gnostic (correct) |
| Decide whether to push (e.g. peer is online via SSE) | **plugins/meinchat** | gnostic |

Core never reads `meinchat.message.protocol` or `meinchat.message.body`. The
meinchat plugin registers a `post_send_hook` that translates its own `Message`
to the opaque APNs envelope core sends.

### Why a `push_dispatcher_registry` and not a direct call?

So a future plugin (e.g. `taro` notifying "your follow-up reading is ready")
can register its own handler without meinchat being a special case. Mirrors
`vbwd/services/checkout_price_adjustment_registry.py` (S36) — already an
established pattern.

## 4. Files

### 4.1 Core (new — vbwd/...)

| Action | Path | Notes |
|---|---|---|
| new | `vbwd-backend/vbwd/models/device_token.py` | columns: `id (uuid)`, `user_id (uuid, fk)`, `token (text, unique)`, `platform (enum: ios)`, `bundle_id (text)`, `app (text)`, `created_at`, `last_seen_at`, `revoked_at (nullable)`. |
| new | `vbwd-backend/alembic/versions/20260610_device_token.py` | creates `device_token` table; indexes `(user_id, app, revoked_at)` and unique on `token`. |
| new | `vbwd-backend/vbwd/repositories/device_token_repository.py` | upsert by token; `find_active_by_user_and_app(user_id, app)`. |
| new | `vbwd-backend/vbwd/services/device_token_service.py` | `register/unregister/mark_seen`. Validates platform ∈ {ios}; trims token; idempotent on duplicate token (refreshes `last_seen_at`). |
| new | `vbwd-backend/vbwd/services/apns_client.py` | ES256-signed JWT (kid + iss + iat), HTTP/2 client (httpx + h2). Sends `apns-push-type: alert`; `apns-topic: <bundle_id>`. Returns per-token `(success: bool, status: int, reason: str?)`. Sandbox endpoint when `VBWD_APNS_USE_SANDBOX=true`. |
| new | `vbwd-backend/vbwd/services/push_dispatcher_registry.py` | `register(app: str, handler: Callable[[PushEvent], None])` · `dispatch(event)` calls each handler in order; handlers may opt out (return None). Mirror of S36's `checkout_price_adjustment_registry.py`. |
| new | `vbwd-backend/vbwd/routes/device_token_routes.py` | `POST /api/v1/devices/register` (auth) — body `{token, platform, bundle_id, app}`; `DELETE /api/v1/devices/<token>` (auth — owner only). |

### 4.2 meinchat consumer (new — plugins/meinchat/...)

| Action | Path | Notes |
|---|---|---|
| new | `plugins/meinchat/meinchat/services/push_notification_hook.py` | `MeinChatPushHook` class with `__call__(msg: Message)`. Reads recipient from `conv`; resolves their active iOS tokens for app `meinchat`; computes badge (sum of `unread_count` from inbox query); builds payload; calls `ApnsClient.send_bulk`. **Suppresses self-pushes** (sender == recipient impossible in a 1-to-1 but guard anyway). |
| edit | `plugins/meinchat/__init__.py` | in `on_enable`: register the hook via the core `push_dispatcher_registry.register("meinchat", MeinChatPushHook(...))`; in `on_disable`: unregister. Also wire `MessageService._run_post_send_hooks` to call the registry. |
| edit | `plugins/meinchat/meinchat/services/message_service.py` | `_run_post_send_hooks` builds a `PushEvent(message, conversation, recipient_user_id, app="meinchat")` and calls `push_dispatcher_registry.dispatch(event)`. **No direct APNs import.** |

### 4.3 Payload shape (gnostic — defined in the meinchat hook only)

```json
{
  "aps": {
    "alert": {
      "title": "@<sender_nickname>",
      "body": "<preview-or-🔒-encrypted-placeholder>"
    },
    "badge": <recipient_total_unread_after_this_msg>,
    "sound": "default",
    "thread-id": "<conversation_id>"
  },
  "conversation_id": "<uuid>",
  "message_id": "<uuid>",
  "protocol": "plain | e2e_v1"
}
```

For `protocol=e2e_v1`: `body = "🔒 New encrypted message"`. **Never** include
the envelope. iOS decrypts on app foreground (S67 §3.5 — NSE is out of scope).

### 4.4 Config (env vars)

Add to `.env.dist`:
```
VBWD_APNS_KEY_PATH=/run/secrets/apns_key.p8
VBWD_APNS_KEY_ID=ABCDE12345
VBWD_APNS_TEAM_ID=TEAMID12345
VBWD_APNS_BUNDLE_ID=com.vbwd.app
VBWD_APNS_USE_SANDBOX=true
```

Document `.p8` mounting in `docker-compose.yaml` as a read-only secret. **Do
not commit the key.** If `VBWD_APNS_KEY_PATH` is unset or unreadable, the
dispatcher logs a single warning at boot and `ApnsClient.send_bulk` is a no-op
(graceful degradation — the rest of the app still works in dev).

## 5. TDD plan (RED first)

### 5.1 Core specs

- `tests/unit/vbwd/services/test_device_token_service.py`
  - `test_register_upserts_by_token_and_refreshes_last_seen`
  - `test_register_rejects_unknown_platform`
  - `test_unregister_marks_revoked_at_and_idempotent`
  - `test_find_active_excludes_revoked`
- `tests/unit/vbwd/services/test_apns_client.py` (`httpx_mock`)
  - `test_send_success_returns_per_token_result`
  - `test_send_bad_token_returns_410_and_marks_revoked` — the client surfaces
    the 410; the **caller** (hook) is responsible for token revocation, NOT
    the client. (Liskov: the client is a transport.)
  - `test_send_uses_sandbox_endpoint_when_flag_set`
  - `test_jwt_payload_has_required_claims`
- `tests/unit/vbwd/services/test_push_dispatcher_registry.py`
  - `test_register_and_dispatch_calls_handler_with_event`
  - `test_unregister_removes_handler`
  - `test_handler_exception_does_not_break_other_handlers` — one raises, the
    rest still run (logged via injected logger).
- `tests/unit/vbwd/routes/test_device_token_routes.py`
  - `test_register_persists_and_returns_201`
  - `test_register_requires_auth`
  - `test_delete_only_owner_can_revoke`

### 5.2 meinchat consumer specs

- `plugins/meinchat/tests/unit/services/test_push_notification_hook.py`
  - `test_plain_message_dispatches_alert_with_preview_and_badge`
  - `test_e2e_message_dispatches_generic_encrypted_placeholder`
  - `test_no_active_tokens_short_circuits_dispatch` (no APNs call)
  - `test_410_bad_token_triggers_unregister` — the hook (not the client)
    revokes a stale token. RED first.

### 5.3 Integration

- `plugins/meinchat/tests/integration/test_push_end_to_end.py` —
  spins the docker stack with a **fake APNs collector** (an httpx mock
  server bound to a localhost port; `VBWD_APNS_*` point at it). Posts a
  message via `POST /messaging/conversations/<id>/messages` and asserts the
  collector received exactly one POST whose JSON matches the payload shape.
  This is the proof end-to-end. RED before §4.2 lands.

### 5.4 Quality gate

`bin/pre-commit-check.sh --full` green on `vbwd-backend`. The
Liskov / agnosticism oracles must still pass: `test_core_agnosticism.py`
asserts no `from plugins.*` import in `vbwd/`; the new core code stays
agnostic.

## 6. Acceptance

- A device with a valid token, a backgrounded app, and a peer who sends a
  plain message receives an APNs push within ~2 s. The payload's `aps.alert.body`
  matches the message preview (up to 120 chars).
- For an `e2e_v1` conversation the body is exactly `"🔒 New encrypted message"`.
  No plaintext or envelope bytes leak in the payload.
- The badge value equals the recipient's total unread message count after the
  new message persists.
- A revoked token (410 from APNs) is marked `revoked_at` in `device_token` and
  is excluded from the next dispatch.
- `bin/pre-commit-check.sh --full` is green on `vbwd-backend`.
- The integration test sends a real-ish APNs POST to the fake collector and
  asserts the JSON shape from §4.3 byte-for-byte.

## 7. Out of scope (follow-ups)

- **Notification Service Extension** (decrypting e2e push payloads in the
  background so the body shows real text on the Lock screen). Needs key
  sharing with an app group + careful Signal-state coordination; defer to its
  own sprint after S67 ships and we have field data on push reliability.
- **Android / web push.** Same `device_token.platform` enum can grow, but
  the dispatcher and routes already accept a `platform` field. Out of scope
  here.
- **fe-user / fe-admin notification UI.** The web has its own SSE channel
  (`MessageService._publish`) — a separate sprint if desktop notifications
  are wanted.
- **Per-user notification preferences** ("mute this conversation",
  "do-not-disturb hours"). Future S6X.
- **Read-receipt suppression for pushed messages.** The iOS NSE work above
  would change this; out of scope for v1.

## 8. Open decisions (resolve at kickoff)

1. **Real APNs vs simulator for dev.** Decision: simulator-only devs use the
   **sandbox endpoint + a real `.p8` key on a personal Apple account** OR the
   **fake collector** wired via `VBWD_APNS_*`. The fake collector is
   sufficient for CI.
2. **Idempotency on duplicate `register`.** Decision: upsert by `token` — if
   another user previously registered the same token (device handoff after
   wipe-and-reinstall), the latest user wins. The integration test pins this.
3. **Hook ordering.** Decision: hooks register a `priority: int = 100`;
   dispatcher sorts ascending. v1 has only `meinchat` — but the seam stays
   ordered so a `taro` hook can declare `priority=50` and run earlier.
