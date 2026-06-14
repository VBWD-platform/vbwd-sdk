# Report 05 — S66 ≡ S67.1: backend device registration + APNs + meinchat push hook

**Date:** 2026-06-11 · **Sprints:** [S66](../../20260610/done/s66-backend-apns-push-notifications.md) (canonical BE design) ≡ [S67.1](../../20260610/done/s67-1-be-device-registration-and-push.md) (BE half of the [S67 umbrella](../../20260610/sprints/s67-notifications-and-badges.md)) — implemented once.
**Repo:** `vbwd-backend` — core `vbwd/` (agnostic mechanism) + `plugins/meinchat` / `plugins/meinchat_plus` (gnostic hooks; plugin code gitignored, on disk).
**Gate:** `bin/pre-commit-check.sh --full` → Part A lint **PASS** · Part B unit **3506 passed, 5 skipped** (agnosticism + vocabulary oracles green) · Part C integration **753 passed, 2 skipped, 1 failed — pre-existing, unrelated** (see Gate notes). TDD-first (all new tests RED before implementation). **Not committed.**

---

## Core mechanism (agnostic — no plugin imports, oracles green)

| File | What |
|---|---|
| `vbwd/models/device_token.py` | `DeviceToken(BaseModel)` — user_id FK (CASCADE), unique `token`, `platform`, `bundle_id`, `app`, `last_seen_at`, nullable `revoked_at`. Table **`vbwd_device_token`** (core `vbwd_` prefix per the S52 `vbwd_api_key` precedent — the sprint's `device_token` name was unprefixed). |
| `alembic/versions/20260610_device_token.py` | Revision `20260610_device_token`, **down_revision `20260606_1000_create_api_key`** — a pure-core anchor (verified nothing else revises it), so the migration runs standalone, plugin-free. Validated up → down → up on the dev DB; now head. Unique index on token + composite `(user_id, app, revoked_at)`. |
| `vbwd/repositories/device_token_repository.py` | `find_by_token`, `find_active_by_user_and_app` (excludes revoked). |
| `vbwd/services/device_token_service.py` | `register` (trims token, platform ∈ {ios}, **upsert by token — latest user wins**, refreshes `last_seen_at`, clears `revoked_at`, never duplicates), `unregister` (idempotent revoke), `mark_seen`, `find_active`. |
| `vbwd/services/apns_client.py` | ES256 JWT (kid/iss/iat, cached ~50 min), httpx HTTP/2 (lazy; `h2==4.1.0` added to requirements), `apns-push-type: alert` + `apns-topic: <bundle_id>`, per-token `(token, success, status, reason)` results, sandbox host on `VBWD_APNS_USE_SANDBOX=true`, missing/unreadable `.p8` → one warning + graceful no-op. **Pure transport — never revokes tokens.** |
| `vbwd/services/push_dispatcher_registry.py` | `PushEvent` dataclass (opaque message/conversation) + `register_push_handler(app, handler, priority=100)` / `unregister` / `dispatch` (ascending priority, handler exceptions logged and contained). Mirrors the S36 `checkout_price_adjustment_registry`. |
| `vbwd/routes/device_token_routes.py` | **`POST /api/v1/devices/register`** (JWT auth, `{token, platform:"ios", bundle_id, app}` → 201, idempotent) · **`DELETE /api/v1/devices/<token>`** (owner-only: 403 non-owner, 404 unknown, 204 ok). Registered + CSRF-exempt in `vbwd/app.py`; DI providers in `vbwd/container.py`. |
| `.env.example` + `docker-compose.yaml` | The five `VBWD_APNS_*` vars (KEY_PATH/KEY_ID/TEAM_ID/BUNDLE_ID/USE_SANDBOX) + a comment documenting read-only `.p8` secret mounting. No key committed. |

## meinchat consumer (gnostic)

- `plugins/meinchat/meinchat/services/push_notification_hook.py` — `MeinChatPushHook`:
  self-push guard → recipient's active tokens for its `app_name` → **badge = Σ unread over the
  same counters the inbox serves** → payload exactly per S66 §4.3 + root `peer_nickname`
  (S67.1 wire contract): `aps.alert.title="@<sender_nickname>"`, body = 120-char preview or
  exactly `"🔒 New encrypted message"` for `e2e_v1` (envelope/plaintext never serialized),
  `aps.badge`, `sound`, `thread-id`, root `conversation_id`/`message_id`/`protocol`.
  **The hook (not the client) revokes a token on APNs 410.** `build_push_hook(app_name)` wires DI.
- `plugins/meinchat/meinchat/services/message_service.py` — `_run_post_send_hooks` additionally
  dispatches `PushEvent(message, conversation, recipient_user_id, app="meinchat")` through the
  core registry; no APNs import; registry contains handler errors so **send can never fail or block**.
- `plugins/meinchat/__init__.py` — `on_enable` registers the hook (key `"meinchat"`), `on_disable` unregisters.
- **meinchat_plus** has no own send path (reuses meinchat's `MessageService`); its `on_enable`
  registers a second hook instance `build_push_hook("meinchat-plus")` so tokens registered with
  `app="meinchat-plus"` are targeted independently (pinned by `test_hook_resolves_tokens_for_its_own_app`).

## Tests (RED-first)

- **Core (33 new):** `test_device_token_service.py` (11 — upsert/no-dup/refresh, non-ios rejected, idempotent revoke, find_active excludes revoked) · `test_apns_client.py` (8 — real ES256 key + `httpx.MockTransport`; 410 surfaced not revoked; sandbox vs production host; JWT kid/alg/iss/iat) · `test_push_dispatcher_registry.py` (6 — priority order, exception isolation) · `test_device_token_routes.py` (8 — 201/400/401/403/404).
- **meinchat unit (7):** preview+badge, 120-char cap, 🔒 placeholder + no-envelope-leak, no-token short-circuit, self-push suppression, 410→revoke, per-app targeting.
- **Integration (2):** `plugins/meinchat/tests/integration/test_push_end_to_end.py` — real users/nicknames/conversation/registered token, then the **real `MessageService.send_text` → hooks → registry → hook → ApnsClient** path with the client's httpx transport as an in-process fake collector; asserts exactly one POST matching §4.3 byte-for-byte (badge, thread-id, peer_nickname, sandbox host, apns headers); plus collector-returns-410 → row revoked + excluded.

## Gate notes

- The single Part C failure (`plugins/ghrm/.../test_ghrm_packages_api.py::test_configured_categories_present`) is **pre-existing and unrelated**: the local untracked `plugins/config.json` lists `software_category_slugs: ["backend", "fe-user"]` (missing `"fe-admin"`) while the test/plugin defaults expect three. Left untouched.
- The gate must run with `GHRM_USE_MOCK_GITHUB=true` (the CI default) — the local `.env` sets it `false`, which produces 9 spurious ghrm failures otherwise ([[project_s50_done_and_gate_e2e_lessons]]).

## Deviations from the sprint doc (rationale)

1. Table named `vbwd_device_token` — core-prefix convention (S52 precedent).
2. Env vars documented in `.env.example` (repo has no `.env.dist`).
3. httpx mocking via injected `httpx.MockTransport` instead of `pytest-httpx` (not installed; same coverage, no new dev dependency).
4. `requirements.txt` gained `h2==4.1.0` (httpx HTTP/2 against real APNs) — rebuild api/test images before pointing at real APNs.

## What's next

**S67.2 (iOS)** can now integrate against the live wire contract (`/devices/register` + payload + badge). Real-device APNs needs a `.p8` key mounted + `VBWD_APNS_*` set (sandbox first).
