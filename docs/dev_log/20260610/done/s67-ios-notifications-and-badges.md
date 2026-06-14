# S67.2 (iOS) — iOS notifications, side-menu badge, and app-icon badge

**Parent:** [S67 umbrella](s67-notifications-and-badges.md). **Depends on:** [S67.1 (BE)](s67-1-be-device-registration-and-push.md) green — this sub-sprint calls `POST /api/v1/devices/register` and renders the S67.1 push payload. **Status:** 🟢 DONE on disk, gates green — 2026-06-12 (see [report 06](../../20260611/reports/06-s67-2-ios-notifications-and-badges.md)); not committed; real-device acceptance (§6) pending. **Repo:**
`vbwd-ios` — host app (`VBWD/`), **core** (`Packages/vbwd-ios-core`),
`Packages/vbwd-ios-plugin-meinchat`, `Packages/vbwd-ios-plugin-meinchat-plus`.
**Engineering requirements (BINDING):** TDD-first · NO OVERENGINEERING ·
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
**Quality gate:** `bash scripts/boundary-lint.sh` + `swift run
VBWDCoreTestsRunner` green + the meinchat package's XCTest suite green.

> **Scope:** the iOS app surfaces only. The backend (`device_token` model, `DeviceTokenService`, `/devices/register`, `ApnsClient`, the meinchat push hook + the push-payload shape) is **S67.1 (BE)** — references below to "the backend" / "S66" mean that sub-sprint. Build against its live wire contract.

---

## 1. Goal (user value)

Three coordinated surfaces, one feature:

1. A push from S66 lands on the Lock screen / banner with sender + preview.
2. The **MeinChat** side-menu entry shows a red pill with the unread total
   (refreshed from the inbox feed, works even with no push).
3. The **app icon** carries the unread count (driven by APNs payload while
   the app is backgrounded; re-asserted from the inbox feed on every
   foreground).

## 2. Current state (grounded)

- `VBWDApp.swift` is a SwiftUI `App` with no `UIApplicationDelegateAdaptor` —
  there's nowhere for `didRegisterForRemoteNotificationsWithDeviceToken` to
  land.
- `VBWD/SupportingFiles/Info.plist` does **not** declare the Push
  Notifications capability; `VBWD.entitlements` does not exist.
- `Packages/vbwd-ios-core/Sources/VBWDCore/Plugins/PlatformSDK.swift` —
  the facade exposes `addRoute`, `addMenuItem`, `addComponent`, … but **no**
  `notifications` seam.
- `MenuItem` (`UI/MenuItem.swift`) has no `badge` field today.
- `Packages/vbwd-ios-plugin-meinchat/Sources/MeinChatPlugin/Views/InboxViewModel.swift`
  already polls `fetchConversations()` and exposes a `conversations:
  [Conversation]` with each row's `unreadCount: Int` — the data is there;
  nothing aggregates it for the badge.
- No `MeinChatEndpoints.deviceRegister` constant.

## 3. Design

### 3.1 Push Notifications capability + entitlement

- Add `VBWD/VBWD.entitlements` with `aps-environment = development` (a
  build-config script flips to `production` for App Store builds).
- Enable the **Push Notifications** capability in Xcode (writes the
  entitlement + signs against the right key).
- `Info.plist`: add `UIBackgroundModes = [remote-notification]` so the
  system delivers silent pushes if we ever opt in (we don't in v1 — but the
  declaration is harmless and pre-S6X NSE doesn't need it).

### 3.2 `UIApplicationDelegateAdaptor` in `VBWDApp`

Smallest possible bridge:

```swift
final class VBWDAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        SDKContainer.shared.notifications.didReceiveDeviceToken(hex)
    }
    func application(_ app: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        SDKContainer.shared.logger.warning("APNs registration failed: \(error)")
    }
}
```

`VBWDApp` adds `@UIApplicationDelegateAdaptor(VBWDAppDelegate.self) var delegate`.
**No business logic in the adaptor** — it forwards into the core seam.

### 3.3 New core seam `PlatformSDK.notifications`

```swift
public protocol NotificationsSDK: Sendable {
    /// Called once per app launch when APNs returns a token.
    func didReceiveDeviceToken(_ tokenHex: String) async
    /// Plugin registers a sink so it can call its own backend endpoint
    /// with the token (e.g. `POST /api/v1/devices/register`).
    func registerSink(_ sink: DeviceTokenSink) async
    /// Drives the app-icon badge. Plugins call this when the inbox feed
    /// reports a new unread total.
    func setAppIconBadge(_ count: Int) async
}

public protocol DeviceTokenSink: Sendable {
    func handleDeviceToken(_ tokenHex: String) async
}
```

Implementation: `DefaultNotificationsSDK` keeps the latest token in memory,
forwards to every registered sink immediately when known, and replays the
last token to any sink that registers later. `setAppIconBadge` calls
`UNUserNotificationCenter.current().setBadgeCount(_:)`.

**Boundary lint:** add `UIApplication`, `UNUserNotificationCenter` to the
allowlist for `Sources/VBWDCore/Notifications/DefaultNotificationsSDK.swift`
ONLY. No leakage outside that file.

### 3.4 `MenuItem.badge` (core)

Add `public let badge: BadgeProvider?` to `MenuItem`, where
`BadgeProvider` is a thin wrapper around an `AsyncSequence<Int>` (or a
`@Published Int` if SwiftUI ergonomics favour it). The shell renders a
small pill next to the label when `badge?.value > 0`. **Default nil** —
zero impact on existing menu items.

### 3.5 meinchat consumer (in `vbwd-ios-plugin-meinchat`)

- `MeinChatEndpoints.deviceRegister = "/devices/register"`,
  `deviceUnregister(token:)`.
- `MeinChatService.registerDeviceToken(_ hex: String, app: String) async throws`
  → POSTs to `/devices/register` with `{token, platform:"ios", bundle_id, app}`.
  Idempotent server-side per S66.
- `MeinChatPlugin.install(_ sdk:)`:
  - `await sdk.notifications.registerSink(MeinChatTokenSink(service: service, app: "meinchat"))`
  - request user authorization on first dashboard mount (NOT in `install`):
    `UNUserNotificationCenter.current().requestAuthorization([.alert, .badge, .sound])`
    + `UIApplication.shared.registerForRemoteNotifications()`. Wrap this in
    `MeinChatNotificationPermissions` (a `@MainActor` helper) that the
    side-menu badge view triggers once per session.
  - drive the menu badge: `addMenuItem(badge: inboxViewModel.unreadTotal)`
    where `unreadTotal` is a `@Published Int` summing
    `conversations.map(\.unreadCount).reduce(0, +)`.
  - on every inbox refresh, call `sdk.notifications.setAppIconBadge(unreadTotal)`.
- On logout: `await service.unregisterDeviceToken(currentTokenHex)` —
  best-effort fire-and-forget so a logout flow isn't blocked by a backend
  hiccup.

### 3.6 meinchat-plus consumer

Identical to §3.5 with `app: "meinchat-plus"`. **No NSE in v1** — the push
payload's body is already the generic placeholder per S66 §4.3, so there's
nothing to decrypt on arrival. When the user opens the app, the inbox
fetch + existing decryption pipeline (S28.7) surfaces the real text.

### 3.7 Foreground notification policy

`UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` on
the host app delegate (or a small router on the plugin side via a sink
extension):

- If `selectedRoute == "/meinchat/<peer>"` and the push's `conversation_id`
  matches the current conversation → return `[]` (suppress banner; mark read
  via the existing ConversationViewModel path).
- Else → return `[.banner, .list, .sound]` (show banner; user gets the
  notification even with the app open).

### 3.8 Tap-to-route

`userNotificationCenter(_:didReceive:)` — extract
`conversation_id` from the payload, plus a `peer_nickname` (TODO: backend
already sends sender_nickname in `aps.alert.title` minus the `@` — keep
it explicit by adding `peer_nickname` to the payload root in S66; updated
that doc). Set `host.selectedRoute = "/meinchat/<peer>?conv=<id>"`. S35 has
already enabled this exact shape on the router side.

## 4. Files

### 4.1 Host app

| Action | Path |
|---|---|
| new  | `VBWD/VBWD.entitlements` |
| edit | `VBWD/SupportingFiles/Info.plist` — `UIBackgroundModes` |
| edit | `VBWD/VBWDApp.swift` — `@UIApplicationDelegateAdaptor` |
| new  | `VBWD/VBWDAppDelegate.swift` — see §3.2 |
| edit | Xcode project — Push Notifications capability + entitlement file ref |

### 4.2 Core (vbwd-ios-core)

| Action | Path |
|---|---|
| new  | `Sources/VBWDCore/Notifications/NotificationsSDK.swift` (protocol) |
| new  | `Sources/VBWDCore/Notifications/DefaultNotificationsSDK.swift` |
| edit | `Sources/VBWDCore/Plugins/PlatformSDK.swift` — expose `notifications` |
| edit | `Sources/VBWDCore/Composition/SDKContainer.swift` — wire `DefaultNotificationsSDK` |
| edit | `Sources/VBWDCore/UI/MenuItem.swift` — `badge: BadgeProvider?` (default nil) |
| edit | `Sources/VBWDCore/UI/SideMenu.swift` — render pill when badge > 0 |
| edit | `scripts/boundary-lint.sh` — narrow allowlist for `UIApplication` / `UNUserNotificationCenter` to the new files only |

### 4.3 meinchat plugins

| Action | Path |
|---|---|
| edit | `…/plugin-meinchat/Sources/MeinChatPlugin/MeinChatEndpoints.swift` — `/devices/register` |
| edit | `…/plugin-meinchat/Sources/MeinChatPlugin/Domain/MeinChatService.swift` — `registerDeviceToken` / `unregisterDeviceToken` |
| new  | `…/plugin-meinchat/Sources/MeinChatPlugin/Notifications/MeinChatTokenSink.swift` |
| new  | `…/plugin-meinchat/Sources/MeinChatPlugin/Notifications/MeinChatNotificationPermissions.swift` |
| edit | `…/plugin-meinchat/Sources/MeinChatPlugin/MeinChatPlugin.swift` — register sink, request auth, drive badge |
| edit | `…/plugin-meinchat/Sources/MeinChatPlugin/Views/InboxViewModel.swift` — `@Published var unreadTotal: Int` |
| edit | `…/plugin-meinchat-plus/…` (mirror) |

## 5. TDD (RED first)

Swift Testing (`@Test`) suites in
`Packages/vbwd-ios-plugin-meinchat/Tests/MeinChatPluginTests/`:

1. `MeinChatTokenSinkTests`
   - `forwards_token_to_service_register`
   - `replays_token_for_late_registered_sink`
   - `unregister_called_on_logout`
2. `InboxViewModelBadgeTests`
   - `unreadTotal_is_sum_of_conversation_unread`
   - `setting_inbox_to_empty_resets_total_to_zero`
3. `MeinChatRouterTests` (extend the S35 file)
   - `tap_payload_routes_to_conversation_with_conv_id` — given a synthetic
     `UNNotificationResponse`-like payload, the routing helper produces the
     expected `/meinchat/<peer>?conv=<id>` string.
4. Core-side (`Packages/vbwd-ios-core/Tests/VBWDCoreTests/`):
   - `DefaultNotificationsSDKTests.replays_latest_token_to_new_sink`
   - `DefaultNotificationsSDKTests.set_app_icon_badge_clamps_negative_to_zero`
   - `MenuItemBadgeTests.menu_renders_pill_when_badge_positive` (via a
     headless SwiftUI snapshot — only if we already have a snapshot harness;
     otherwise a unit test on the badge view's `body` text content).

All XCTest-free where possible; reuse the existing
`VBWDCoreTestsRunner` harness for core specs.

## 6. Acceptance

- Building the host app on a real device requests push authorization on
  first dashboard load. Granting → APNs token reaches `MeinChatTokenSink`
  → backend `POST /devices/register` returns 201 (S66 §6).
- Sending a message from peer A's device to peer B's device while B's app is
  backgrounded → push lands within ~2 s with `@<sender_nickname>` title and
  the message preview (or 🔒 placeholder for e2e_v1).
- Tapping the push opens the conversation directly (uses S35 routing).
- The MeinChat side-menu entry shows a red pill with the total unread; the
  pill disappears when all conversations are read.
- The app icon shows the same badge number. Clearing all unread (mark all
  read from inbox swipe or open + mark each) drops both badges to zero.
- `bash Packages/vbwd-ios-core/scripts/boundary-lint.sh` is green — no
  `UNUserNotificationCenter` or `UIApplication` reference outside the two
  allowlisted files.
- `swift run VBWDCoreTestsRunner` green; package XCTest suites green; the
  6 S35 specs from yesterday still green.

## 7. Out of scope (follow-ups)

- **Notification Service Extension** to decrypt e2e payloads in the
  background. Sprint of its own — needs key sharing via App Group + careful
  Signal-state coordination.
- **Critical Alerts / time-sensitive entitlement** (needs Apple approval).
- **macOS / Catalyst notification surface.** The same SDK seam works on
  macOS but the entitlement story differs; deferred.
- **Per-conversation mute / DND hours.** Future sprint.
- **Web fe-user notifications.** Different transport (Web Push or SSE
  banners) — out of scope here.

## 8. Open decisions (resolve at kickoff)

1. **When to request `requestAuthorization`.** v1: first time the user
   lands on the dashboard, AFTER login. **Not** at app launch (worse
   conversion). A `MeinChatNotificationPermissions.askOnce()` helper guards
   this via UserDefaults so re-launches don't re-prompt.
2. **`UIBackgroundModes = [remote-notification]` in v1?** Yes — harmless,
   future-proofs the NSE follow-up.
3. **BadgeProvider shape: `AsyncSequence<Int>` vs `@Published Int`?**
   Lean to `@Published Int` for SwiftUI ergonomics; if a non-SwiftUI shell
   ever consumes this, wrap it then. NO OVERENGINEERING — pick the
   ergonomic one now.

## 9. Risk + mitigation

- **Token churn after wipe-and-reinstall**: APNs may issue a new token; the
  old one becomes a 410. S66 §5.2 handles this; iOS does not need code
  beyond re-running `registerForRemoteNotifications()` on each launch (we
  do this already in §3.2).
- **Signing / provisioning profile flake**: Xcode Cloud sometimes silently
  drops the `aps-environment` entitlement if the profile is regenerated
  with the wrong checkboxes. Acceptance §6 covers a real-device end-to-end
  proof — that catches the misconfig immediately.
- **Race between APNs token arrival and login**: token can arrive before
  the user is authenticated. The sink buffers (replays on register) and
  the meinchat plugin only triggers the sink AFTER auth, so the register
  POST always carries a JWT.
