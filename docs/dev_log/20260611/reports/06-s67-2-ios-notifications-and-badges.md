# Report 06 — S67.2 (iOS): notifications, side-menu badge, app-icon badge

**Date:** 2026-06-12 · **Sprint:** [S67.2](../../20260610/done/s67-ios-notifications-and-badges.md) — the iOS half of the [S67 umbrella](../../20260610/done/s67-notifications-and-badges.md); consumes the live S67.1 wire contract ([report 05](05-s66-s67-1-backend-apns-push.md)). **The whole S67 feature is now done on disk** (real-device end-to-end proof pending).
**Repos:** `vbwd-ios` host (`VBWD/` + vendored `Packages/vbwd-ios-core`) + the `meinchat` / `meinchat-plus` plugin submodules — all on disk, **nothing committed**.
**Gates:** `boundary-lint.sh` **OK** · `swift run VBWDCoreTestsRunner` 573 passed (+11 new; failures byte-identical to pre-sprint baseline) · meinchat suite **58 passed / 0 failed** (xcodebuild, iPhone 17 sim) incl. all 14 new + all S35 router specs · meinchat-plus 40 passed incl. all 4 new (5 pre-existing keychain-entitlement env failures) · app target **BUILD SUCCEEDED** with `aps-environment=development` confirmed in the generated `.xcent`. TDD-first.

---

## What was built (sprint §3–§4)

**Host app**
- `VBWD/VBWD.entitlements` (`aps-environment = development`) wired into `project.pbxproj` (`CODE_SIGN_ENTITLEMENTS`, Debug+Release; `plutil -lint` clean — `VBWD/` is a filesystem-synchronized group so new files auto-join the target).
- `Info.plist`: `UIBackgroundModes = [remote-notification]`.
- `VBWDAppDelegate.swift` + `@UIApplicationDelegateAdaptor` in `VBWDApp.swift`: APNs token → hex → core notifications seam (no business logic); `registerForRemoteNotifications()` on every launch; `UNUserNotificationCenterDelegate` foreground policy (suppress banner only when the matching conversation is open) + tap-to-route via the plugin's routing helper, with a `pendingRoute` buffer for cold-start taps.

**Core (`vbwd-ios-core`)**
- New `Notifications/` seam: `NotificationsSDK` protocol + `DefaultNotificationsSDK` (actor — buffers the latest token, **replays it to late-registering sinks**, badge via injectable closure with negative-clamp; `static shared` bridges the UIKit delegate to DI). Exposed as `sdk.notifications` on the `PlatformSDK` facade, wired in `SDKContainer`/`PluginHost`.
- `BadgeProvider` (`@MainActor ObservableObject`, `@Published count` — the sprint §8.3 ergonomic choice); `AppShellMenuItem.badgeProvider` (default nil, zero impact on existing items); `MenuBadgePill` red pill rendered in the side menu when count > 0.
- `AuthSession.signOut()` now emits `AppEvents.authLogout` (constant existed but was never emitted — needed for unregister-on-logout).
- **`boundary-lint.sh` was silently dead** (scanned a non-existent `Sources/VBWDSdk` path) — fixed to scan `Sources/VBWDCore`, and extended: `UNUserNotificationCenter` allowlisted only in `DefaultNotificationsSDK.swift`; `UIApplication` there + the pre-existing `PaymentRedirectView.swift` key-window lookup the dead lint never caught.

**meinchat plugin** — `MeinChatEndpoints.deviceRegister`/`deviceUnregister(token:)`; `MeinChatService.registerDeviceToken/unregisterDeviceToken` (POST `{token, platform:"ios", bundle_id, app}` via `sdk.api`); `MeinChatTokenSink` (actor, **auth-gated: buffers the token until `authLogin` so the POST always carries a JWT**, re-registers on re-login, best-effort unregister on logout); `MeinChatNotificationPermissions.askOnce()` (UserDefaults-guarded, triggered on login — not in `install`, §8.1); `MeinChatNotificationRouting` (pure payload → `/meinchat/<peer>?conv=<id>` + banner-suppression predicate, used by the host delegate); `InboxViewModel.unreadTotal` (`@Published`, Σ `unreadCount`) drives both the menu `BadgeProvider` and `sdk.notifications.setAppIconBadge` on every inbox refresh.

**meinchat-plus** — mirror with `app: "meinchat-plus"` (own token sink, permissions helper with its own UserDefaults key — a second `requestAuthorization` resolves silently, no double prompt). No badge mirror (no menu item/inbox there). No NSE in v1.

## New tests (23)

Core runner `S67_Suites_Notifications` (11 assertions: token replay to late sink, badge clamp, provider/pill behavior) · meinchat: `MeinChatTokenSinkTests` (5), `InboxViewModelBadgeTests` (4), +5 S35 `MeinChatRouterTests` payload/suppression specs · meinchat-plus: `MeinChatPlusTokenSinkTests` (4).

## Deviations from the sprint doc

1. §3.2's `SDKContainer.shared.notifications` — no shared container exists; `DefaultNotificationsSDK.shared` is the process-wide token relay (the container exposes the same instance); tap-routing uses a weak `SDKContainer.pluginHost` + `.onAppear` wiring. Token delivery never depends on that wiring (buffered + replayed).
2. `MenuItem` already had a static `badge: String?` — `badgeProvider` added alongside rather than replacing (lesson L1: modify in place, don't break existing users).
3. The sink registers in `install` but is auth-gated internally — same §9 guarantee (register POST always authenticated), simpler than deferred registration, and covers re-login re-registration.

## Pre-existing issues surfaced (not caused here, not fixed beyond the noted one)

- `MessageCacheTests` (S28.6) crashes the meinchat suite on this toolchain (`NSBatchDeleteRequest` vs in-memory CoreData store) — gate run skipped that one suite.
- `ConversationViewModelMergeTests` didn't compile under Xcode 26.5 (MainActor isolation) — fixed with a one-line `@MainActor` since it blocked the whole suite build.
- CLI `swift test` of the plugin packages targets macOS and fails on unguarded UIKit — iOS `xcodebuild` is the working path.
- Core runner's 11 baseline failures (4 keychain CLI-env, 7 S6 suites) — byte-identical before/after, verified by diff.

## Not verifiable CLI-side (open acceptance, sprint §6)

Real-device proof: push delivery ≤2 s with `@sender` + preview/🔒, lock-screen render, tap-open, badge sync, 410 token churn — needs a physical device, an Apple-portal Push capability on the provisioning profile, and a mounted `.p8` on the backend (sandbox first).
