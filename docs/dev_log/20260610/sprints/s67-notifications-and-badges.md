# S67 — Notifications & badges (umbrella)

**Status:** PLANNED — 2026-06-10 (split BE/iOS 2026-06-11). One feature, two repos. **Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · NO OVERENGINEERING — [`_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

## Goal (user value)

When user A messages user B in **meinchat** (or **meinchat-plus**), B's iOS device gets an **APNs push** (lock screen / banner with sender + preview, or a 🔒 placeholder for `e2e_v1`); the **MeinChat side-menu entry** shows a red unread pill; and the **app icon** carries the unread badge. Tapping the push opens the conversation. All three surfaces stay in sync from the inbox feed even without a push.

## Split (BE ↔ iOS)

This feature is split into two sub-sprints so the backend and the iOS app land independently against a stable wire contract:

| # | Sub-sprint | Repo | Gate |
|---|---|---|---|
| **S67.1 (BE)** | [Device registration + APNs + push hook](s67-1-be-device-registration-and-push.md) | `vbwd-backend` (core `vbwd/` mechanism + `plugins/meinchat` hook) | `bin/pre-commit-check.sh --full` green |
| **S67.2 (iOS)** | [iOS app: notifications, side-menu badge, app-icon badge](s67-ios-notifications-and-badges.md) | `vbwd-ios` (host app + `vbwd-ios-core` + meinchat / meinchat-plus packages) | `boundary-lint.sh` + `VBWDCoreTestsRunner` + package XCTest green |

**S67.1 (BE) is the same backend scope as the pre-existing [S66 — Backend APNs](s66-backend-apns-push-notifications.md)** — S66 is the detailed backend design; S67.1 is that work restated as the BE half of this feature with the iOS-facing contract pinned. Implement the backend once (S66 = S67.1); don't double-build. **S67.2 (iOS) depends on S67.1** being green (it calls `/devices/register` and renders the push payload).

## Wire contract (the seam between the two)

- **Register:** `POST /api/v1/devices/register` (auth) — body `{token, platform:"ios", bundle_id, app}`; idempotent (upsert by token, refresh `last_seen_at`). **Unregister:** `DELETE /api/v1/devices/<token>` (auth, owner-only).
- **Push payload (S66 §4.3):** `aps.alert.title = "@<sender_nickname>"`, `aps.alert.body = <preview | "🔒 New encrypted message">`, `aps.badge = <unread total>`, plus root `conversation_id` + `peer_nickname` for tap-to-route (S35 router shape `/meinchat/<peer>?conv=<id>`).
- **Badge source:** the unread total = Σ `conversation.unread_count` from the inbox feed; the backend asserts it in `aps.badge` on push, iOS re-asserts it from the inbox feed on every foreground.

## End-to-end acceptance

A real-device build requests push auth after first dashboard load → APNs token reaches `MeinChatTokenSink` → `POST /devices/register` returns 201. A→B message while B is backgrounded → push within ~2 s with `@sender` + preview (or 🔒). Tap opens the conversation. The side-menu pill and the app-icon badge both show the unread total and drop to zero when all is read. Both gates green.

## Out of scope (shared follow-ups)
NSE to decrypt `e2e_v1` in the background · Critical Alerts / time-sensitive entitlement · macOS/Catalyst surface · per-conversation mute/DND · web fe-user notifications (different transport).
