# S67.1 (BE) — Device registration + APNs + meinchat push hook

**Parent:** [S67 umbrella](s67-notifications-and-badges.md). **Repo:** `vbwd-backend` — **core `vbwd/`** for the generic device-token mechanism, **`plugins/meinchat`** for the consumer hook (+ `meinchat-plus` mirror). **This is the same backend scope as [S66 — Backend APNs](s66-backend-apns-push-notifications.md)** — S66 is the full design + file/test list; this doc is the BE sub-sprint entry of S67 with the iOS-facing contract pinned. **Implement once (S66 ≡ S67.1); do not double-build.** **Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · NO OVERENGINEERING. **Gate:** `bin/pre-commit-check.sh --full` green on `vbwd-backend` + agnosticism/vocabulary oracles green.

## Why split it out

The iOS app (S67.2) only needs a stable **wire contract** to register tokens and render pushes; the backend can land first and independently. Mechanism stays in **core** (agnostic device-token + APNs), meaning stays in the **meinchat plugin** (the push hook) — the same core-vs-plugin separation S52 used for API keys.

## Scope (mechanism in core, meaning in plugin)

| Concern | Owner | Agnostic |
|---|---|---|
| `device_token` model (`user_id, token, platform, bundle_id, app, created_at, last_seen_at, revoked_at`) | core | yes — no domain fields |
| `DeviceTokenService.{register, unregister, find_active_by_user_and_app, mark_seen}` | core | yes |
| `POST /api/v1/devices/register` (auth) · `DELETE /api/v1/devices/<token>` (auth, owner-only) | core | yes |
| `ApnsClient` (HTTP/2 + ES256 JWT, `apns-topic=<bundle_id>`, sandbox flag) | core | yes |
| `MeinChatPushHook` (registered on the existing `_run_post_send_hooks` seam) — resolve recipient's active iOS tokens for `app`, compute badge, build payload, `ApnsClient.send_bulk`, revoke on 410 | `plugins/meinchat` (+ `meinchat-plus`) | no (meinchat-gnostic) |

Full file + migration + test breakdown: **see [S66](s66-backend-apns-push-notifications.md) §4–§5** (e.g. `vbwd/models/device_token.py`, `alembic/versions/20260610_device_token.py`, `vbwd/services/{device_token_service,apns_client}.py`, `vbwd/routes/device_token_routes.py`, `plugins/meinchat/.../push_notification_hook.py`). Do not restate here — that file is canonical.

## Wire contract this sub-sprint MUST deliver (consumed by S67.2 iOS)

1. **Register** — `POST /api/v1/devices/register`, auth (JWT), body `{token, platform:"ios", bundle_id, app}` → **201**; idempotent (upsert by `token`, refresh `last_seen_at`, never duplicate). `platform ∈ {ios}` validated; token trimmed.
2. **Unregister** — `DELETE /api/v1/devices/<token>`, auth, owner-only → 204; a stale token surfaced as APNs **410** is revoked by the **hook** (caller), not the client.
3. **Push payload** — `aps.alert.title="@<sender_nickname>"`, `aps.alert.body=<preview | "🔒 New encrypted message">` (the latter for `protocol=e2e_v1` — server can't decrypt), `aps.badge=<unread total>`; root `conversation_id` + `peer_nickname` (for the S35 tap-route `/meinchat/<peer>?conv=<id>`). `apns-push-type: alert`, `apns-topic: <bundle_id>`.
4. **Badge** — unread total = Σ recipient's `conversation.unread_count` from the inbox query; asserted in `aps.badge`. Self-push suppressed.
5. **Per-app** — `app ∈ {meinchat, meinchat-plus}` so each app's tokens are targeted independently (the hook resolves tokens for its `app`).

## TDD (RED first) — see S66 §5 for the full list; the iOS-facing musts:
- `register` upserts by token + refreshes `last_seen_at` (no duplicate rows); rejects non-`ios` platform.
- `DELETE /devices/<token>` is owner-only (403 for a non-owner).
- the hook builds the `e2e_v1` → 🔒 body and the plain → preview body; sets `aps.badge` = the inbox unread sum; suppresses self-push; revokes a token on a 410 from `ApnsClient`.
- `ApnsClient` uses the sandbox endpoint when `VBWD_APNS_USE_SANDBOX=true`.

## Constraints (BINDING)
TDD-first · SOLID/Liskov (the push hook is one of N `_run_post_send_hooks`; absent push config = no-op, never blocks send) · DI · DRY · **NO OVERENGINEERING** · core device-token mechanism stays **agnostic** (oracles green) · secrets (`.p8`, kid/iss) via env, never committed · idempotent register · do not duplicate S66 (it is canonical).

## Gate (done)
`bin/pre-commit-check.sh --full` green on `vbwd-backend` + oracles green; the 5 wire-contract items above are demonstrated by tests. Then S67.2 (iOS) can integrate against the live `/devices/register` + payload.
