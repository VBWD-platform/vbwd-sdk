# S28.7 — iOS `meinchat-plus` plugin (Signal client + device pairing) — **enabled at v1 launch**

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. iOS sibling of the web client in
[S28.3b](s28-3b-meinchat-plus-signal-ratchet.md) §4 — the actual
Signal-protocol client lives here.

**Launch posture — decided 2026-05-28 (S28 decision R2-Q1):**
meinchat-plus ships as a **default-ON feature** when vbwd.cc v1
launches — the bundled `plugins.json.dist` carries
`"meinchat-plus": { "enabled": true }`. Existing beta-RC TestFlight
builds (`MARKETING_VERSION 1.0`) get the plugin in the next
TestFlight bump (`MARKETING_VERSION 1.1`, `CURRENT_PROJECT_VERSION 2`)
already enabled — there is NO opt-in gating phase.

**v1-launch risk acknowledged.** A crypto bug in S28.7 is a
release-blocker, not a beta-rollback — the TDD spec set + the
critical-review revision absorbed into S28.3b/S28.7 are the safety net.
The `DisableRestoresPlainTests` regression net (§4.8) stays — but as a
**user-can-opt-out check** (Settings → Plugins → meinchat-plus →
disable), not a TestFlight rollback mechanism. If a launch-day
issue surfaces, an operator can disable the plugin per-instance via
the existing admin UI; users can disable it per-device via Settings.

Existing `vbwd-ios/VBWD` users who never disable it see E2E from day
one of v1. Beta-RC TestFlight users in the gap before v1 see the
plugin enabled in the 1.1 build.
**Depends on:** [S28.3b](s28-3b-meinchat-plus-signal-ratchet.md)
(backend wire contract, including `SignalEnvelopeValidator` +
device-key tables + prekey routes + downgrade error contract),
[S28.6](s28-6-ios-meinchat-app-update-plan.md) (`MeinChatLimitsService`
+ `MessageCache` + `ClientRetentionResolver` infra reused here).
**Blocks:** the S28 milestone "two users, web ↔ iOS, exchange E2E
ciphertext via the same instance" acceptance — both clients must be
live for the round-trip smoke.

**Repos touched (NEW):** `vbwd-ios/VBWD/Packages/vbwd-ios-plugin-meinchat-plus/`.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY ·
Liskov · clean code · **NO OVERENGINEERING** —
[`_engineering_requirements.md`](_engineering_requirements.md).
**Gate:** `swift test` GREEN on the new package;
`mcp__xcode-tools__BuildProject` GREEN on the host app with the new
plugin both **enabled** and **disabled** (the latter is the beta-RC
no-regression check); integration round-trip GREEN against a backend
running S28.3b + S28.6 against a real PostgreSQL.

---

## 1. Goal (user value)

When the user enables `meinchat-plus` on iOS:

1. Their device generates an X3DH identity keypair + signed prekey +
   100 one-time prekeys client-side, registers the public halves to
   the backend, and is **ready for E2E** within seconds.
2. New conversations started with `accepted_protocols: ["e2e_v1"]`
   succeed when the peer also has at least one active device; **fail
   closed** otherwise (no silent plaintext fallback).
3. Composing a message in an `e2e_v1` conversation: the body is
   padded to a 256-byte multiple, encrypted client-side for every
   addressed device (peer's + own), packed as CBOR, and POSTed as an
   opaque envelope — the iOS app **never** sends plaintext for an
   `e2e_v1` conversation.
4. Receiving a message: the client picks its own slot from the
   envelope, decrypts, strips padding, paints. The server-returned
   bytes contain nothing the local recipient can't open.
5. Settings → meinchat-plus shows the device label, pairing time, "1
   active device" / "3 of 100 one-time prekeys remaining" status, and
   a Revoke + Re-pair button.

**v1-launch constraints** drive every design choice:
- Brand-new plugin package; bundled `plugins.json` entry marked
  `enabled: true` in the host app's `plugins.json.dist` (default-on at
  v1 launch).
- No host-shell code change. No `VBWDCore` SDK API change.
- One new Swift package dependency: `LibSignalClient`. Vendored locally
  per CLAUDE.md "no external Swift package dependencies" — the
  `LibSignalClient` source is committed into
  `Packages/vbwd-ios-plugin-meinchat-plus/Vendored/LibSignalClient/`.
- The plugin is enable/disable-able at runtime via the existing
  `BundledPluginManifestLoader` + Settings → Plugins surface.
  Disabling restores meinchat-alone behaviour cleanly — the
  user-opt-out path (and the operator-disable-per-instance path).

## 2. Current state (proof of pain)

- The web client side of meinchat-plus exists as a plan
  (S28.3b §3). The iOS side is the missing client. Without it the
  backend's `e2e_v1` capability is half-live: an iOS user is the
  "peer who has no device keys" forever.
- iOS Keychain + CryptoKit + URLSession are already used by other
  plugins (stripe, subscription) — patterns established.
- `vbwd-ios-plugin-meinchat` does not import any crypto library
  today, so the new dependency lands cleanly in a new package without
  bloating the existing meinchat plugin's footprint.

## 3. Design

A new Swift package mirroring the existing
`Packages/vbwd-ios-plugin-meinchat` layout:

```
vbwd-ios-plugin-meinchat-plus/
├── Package.swift
├── Sources/MeinChatPlusPlugin/
│   ├── MeinChatPlusPlugin.swift           # @main entry; conforms to PluginProtocol
│   ├── Domain/
│   │   ├── SignalClient.swift             # libsignal wrapper
│   │   ├── DeviceIdentity.swift           # keypair + label + storage
│   │   ├── PrekeyStore.swift              # signed + one-time prekeys
│   │   ├── EnvelopePacker.swift           # CBOR pack/unpack matching S28.3b
│   │   ├── Padding.swift                  # 256-byte multiple
│   │   ├── SecureSendService.swift        # send flow: pad → encrypt → fan-out → POST
│   │   ├── SecureReadService.swift        # read flow: pick slot → decrypt → strip pad
│   │   └── DowngradeGuard.swift           # fail-closed on conv response
│   ├── Storage/
│   │   ├── KeychainIdentityStore.swift    # device identity private key
│   │   └── CoreDataSessionStore.swift     # Signal session per peer device
│   ├── Views/
│   │   ├── PairingSheet.swift             # first-launch passphrase setup
│   │   ├── ComposerPrecheck.swift         # peer-has-no-device-keys hint
│   │   ├── RevokeDeviceButton.swift       # settings action
│   │   └── PrekeyStatusRow.swift          # "3 of 100 remaining"
│   └── Vendored/
│       └── LibSignalClient/               # vendored per CLAUDE.md
└── Tests/MeinChatPlusPluginTests/
    ├── PaddingTests.swift
    ├── EnvelopeRoundTripTests.swift
    ├── KeyRegistrationFlowTests.swift
    ├── DowngradeFailClosedTests.swift
    ├── OwnDeviceDecryptTests.swift
    ├── ComposerPrecheckTests.swift
    ├── KeychainStorageClassTests.swift
    └── DisableRestoresPlainTests.swift
```

### 3.1 Pairing (`Views/PairingSheet.swift` + `Domain/DeviceIdentity.swift`) — **biometric primary, passphrase fallback** (S28 decision R1-Q3)

The KEK that wraps the device identity private key + the cached
message payloads (shared with S28.6's `MessageCache`) is held in
Keychain under **two access-control entries**:

1. **Primary path — biometric-gated.** A Keychain entry with
   `kSecAccessControlBiometryCurrentSet` + `.userPresence` (Face ID /
   Touch ID required on every read). `LAContext.evaluatePolicy(.
   deviceOwnerAuthenticationWithBiometrics, ...)` gates per-send
   access. Zero passphrase friction on the happy path.
2. **Fallback path — passphrase-derived.** A *second* Keychain entry,
   sealed under a KEK derived from a passphrase the user sets at
   pairing time (Argon2id 64 MB / 3 iters via `CryptoKit`'s
   primitives — Apple ships HKDF + SHA-256; Argon2id is wrapped via a
   small vendored library shared with the web KEK choice
   [s28-3b §3.2]). Used **only** when:
   - The user resets biometrics (passcode change invalidates
     `BiometryCurrentSet` → primary entry is gone).
   - The device is restored from backup (Keychain item with
     `ThisDeviceOnly` is non-portable; biometric primary did not
     survive the restore).
   - The user opts to enter the passphrase manually (Settings →
     meinchat-plus → "Use passphrase this session").

The KEKs in (1) and (2) are **the same 256-bit value** — both
Keychain entries seal the same key under different access controls.
On pairing the key is generated once, sealed twice. The fallback
entry's class is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(matches S28.6's cache key class — same Keychain item ID; one
Keychain entry, two consumers per S28.6 §7).

On first plugin enable:

1. User chooses pairing mode in `PairingSheet`:
   - **Default ("Use Face ID / Touch ID"):** prompt for biometric
     consent; on success, generate KEK + seal under both Keychain
     entries; also prompt the user to set a recovery passphrase
     (used only if biometrics are reset or the device is restored).
   - **Power-user ("Use passphrase only"):** skip the biometric
     entry; KEK lives only in the fallback Keychain entry. Two-tap
     UX trade-off; meaningful for users with biometrics disabled
     for unrelated reasons.
2. Generate `IdentityKeyPair`, `SignedPreKeyRecord`, and 100
   `PreKeyRecord`s client-side via `LibSignalClient`.
3. The private identity key + private prekeys live in Keychain
   sealed under the KEK.
4. `POST /me/devices` (public key + label), `POST /me/prekeys/signed`,
   `POST /me/prekeys/one-time`.
5. Surface "Secure chat ready" toast and "Pairing complete" row in
   settings.

The server **never** sees a private key. The recovery passphrase is
never transmitted — it's a local Keychain-fallback secret.

### 3.2 Send (`Domain/SecureSendService.swift`)

```swift
public func sendSecure(_ plaintext: String, in conv: Conversation) async throws -> ChatMessage {
    guard conv.protocol == "e2e_v1" else {
        throw E2eGuardError.conversationIsNotE2e
    }
    let padded = Padding.padTo256(plaintext)
    let peerDevices = try await api.get("/messaging/users/\(conv.peerUserID)/devices")
        as [DeviceDescriptor]
    let ownDevices  = try await api.get("/messaging/users/\(currentUserID)/devices")
        as [DeviceDescriptor]
    let addressed = peerDevices + ownDevices.filter { $0.id != self.identity.localDeviceID }
    let slots = try await addressed.asyncMap { device in
        let session = try await sessionStore.session(for: device)
        return Envelope.Slot(
            deviceID: device.id,
            header:    try session.headerFor(padded),
            ciphertext: try session.encrypt(padded),
        )
    }
    let envelope = EnvelopePacker.pack(.init(v: 1, perRecipient: slots))
    return try await api.post("/messaging/conversations/\(conv.id)/messages",
                              body: ["envelope_b64": envelope.base64EncodedString()])
}
```

Sender includes own active devices in the recipient set (closes
critical-review §C7). All crypto on-device.

### 3.3 Read (`Domain/SecureReadService.swift`)

```swift
public func decryptIncoming(_ row: ChatMessage) throws -> String {
    guard row.protocol == "e2e_v1", let envelopeB64 = row.envelopeB64 else {
        throw E2eGuardError.notAnE2eMessage
    }
    let envelope = try EnvelopePacker.unpack(Data(base64Encoded: envelopeB64)!)
    guard let mySlot = envelope.perRecipient.first(where: { $0.deviceID == identity.localDeviceID })
    else { throw E2eGuardError.noSlotForThisDevice }
    let session = try sessionStore.session(for: row.senderDevice)
    let padded = try session.decrypt(ciphertext: mySlot.ciphertext, header: mySlot.header)
    return Padding.strip(padded)
}
```

### 3.4 Downgrade fail-closed (`Domain/DowngradeGuard.swift`)

`startE2eConversation(peer:)` posts
`accepted_protocols: ["e2e_v1"]`. If the response
`conversation.protocol != "e2e_v1"`, the service throws
`ProtocolDowngradeError`, the UI shows a warning sheet, and the
conversation is never persisted in the local meinchat-plus state.
Closes critical-review §C14.

### 3.5 Plugin lifecycle (`MeinChatPlusPlugin.swift`)

```swift
@main
public final class MeinChatPlusPlugin: PluginProtocol {
    public static let id = "meinchat-plus"
    public static let dependencies = ["meinchat"]

    public func bootstrap(sdk: PlatformSDK) {
        let limits   = sdk.store(of: MeinChatLimitsServiceProtocol.self)   // S28.6 reuse
        let identity = KeychainIdentityStore(/* shared KEK */)
        let sessions = CoreDataSessionStore(/* protected store */)
        let prekeys  = PrekeyStore(api: sdk.api, libsignal: LibSignalClient())
        let sendSvc  = SecureSendService(api: sdk.api, identity: identity,
                                         sessionStore: sessions)
        let readSvc  = SecureReadService(identity: identity, sessionStore: sessions)
        // Hook into meinchat-side store: when conv.protocol == "e2e_v1",
        // route through sendSvc/readSvc instead of the plain path.
        sdk.routeOverride(forProtocol: "e2e_v1", send: sendSvc, read: readSvc)
        sdk.registerSettingsRow(PrekeyStatusRow(prekeys: prekeys))
        sdk.registerSettingsAction(RevokeDeviceButton(api: sdk.api, identity: identity))
    }

    public func teardown(sdk: PlatformSDK) {
        sdk.removeRouteOverride(forProtocol: "e2e_v1")
        // Identity stays in Keychain — re-enable picks up the same device.
    }
}
```

`sdk.routeOverride(...)` uses an **existing** `PlatformSDK` extension
point (the same one stripe / subscription plugins use). No new SDK
API.

### 3.6 Delivery + read receipts UI (`Views/ChatBubbleReceipts.swift`)

The message bubble for **outgoing** messages (sender = current user)
renders **0 / 1 / 2 small dots** in the bottom-right corner — WhatsApp
single-tick / double-tick style. The same UI works for plain AND
e2e_v1 conversations (the data model is protocol-agnostic per the
S28.3a addendum referenced below; iOS reads `message.delivered_at`
and `message.read_at` regardless of protocol).

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
| NULL | NULL | (none) | The server accepted the message but the recipient hasn't fetched it yet. Transient. |
| not NULL | NULL | • | The recipient's client has fetched the message (i.e. `GET /messages` returned it). |
| not NULL | not NULL | • • | The recipient explicitly marked the message read — they opened the conversation and the message scrolled into view. |
| NULL | not NULL | • • | Impossible by design (server-side CHECK: `read_at IS NULL OR delivered_at IS NOT NULL`). |

When the local user opens a conversation and a message scrolls into
view, the iOS client `POST /messaging/messages/<message_id>/read` to
mark it as read. The endpoint is **idempotent** — repeat calls on the
same `(message_id, user_id)` are no-ops after the first.

For **e2e_v1 conversations**, the same UI applies. The
`delivered_at` is set when the recipient's device fetches AND
decrypts (post-S28.3b §2.4) — i.e. it tracks application-level
delivery, not just bytes-fetched. This means a corrupted envelope
that fails to decrypt does NOT mark the message as delivered (the UI
correctly shows "still sending" until the recipient's client can
actually read the body).

### 3.6.1 Backend prerequisite

The receipt UI requires two `message`-table columns + one new route
on the backend:

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

For e2e_v1, the message-level `delivered_at` is independent of
`meinchat_plus_message_delivery.fetched_at` (which is per-device,
for the prune predicate). One home for UI receipts (`message`
columns), one home for the prune predicate (`meinchat_plus_message_delivery`
table). DRY: each table answers one question.

**This backend work is added to [S28.3a](s28-3a-meinchat-extension-ports.md)
as an additive schema concession + two routes.** Pinned by S28.3a's
acceptance gate.

### 3.6.2 SwiftUI implementation

`Views/ChatBubbleReceipts.swift`:

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

### 3.6.3 Marking as read — `ConversationViewModel`

When a message becomes visible in the scroll view, the VM debounces
and posts `POST /messages/<id>/read` after the message has been
on-screen for ≥ 250 ms (so a rapid scroll-past doesn't fire). Uses
`onAppear` on the `ChatMessageBubble` + a `Task.detached` timer.

### 3.6.4 Web (fe-user) mirror

The same UI is added to `vbwd-fe-user/plugins/meinchat/src/components/MessageBubble.vue`
in a coordinated edit landing alongside this sprint. See **the
"fe-user mirror" addendum to [S28.2](s28-2-client-local-cache.md)**
(client-cache slice — same plugin tree). One CSS class, two
`<span class="dot">` elements when `deliveredAt`/`readAt` cross
their thresholds.

### 3.7 NO OVERENGINEERING — what we DID NOT add

- **No background fetch of unread E2E messages.** Existing meinchat
  polling covers it.
- **No second key store.** One per-device KEK in Keychain is the only
  long-term secret on the device.
- **No iOS-side `LibSignalClient` fork.** Vendored verbatim per
  CLAUDE.md.
- **No new `PlatformSDK` extension point.** `routeOverride(forProtocol:)`
  already exists.
- **No automatic `WhenUnlocked` toggle.** Per the parent sprint §11
  decision-locked.
- **No on-device telemetry of message lengths or send timing** (would
  defeat the operator-blind goal even partially).
- **No group-chat support.** S28 master §3.A is 1:1 only.

## 4. TDD plan

Inside `Tests/MeinChatPlusPluginTests/`. All XCTest, no UITest in this
sprint (the round-trip UITest lives in the host app's UITest suite
once both clients merge).

### 4.1 `PaddingTests.swift` (NEW, ≥ 3 specs)

1. Pad-then-strip recovers the original string byte-for-byte.
2. Padded length is always a multiple of 256.
3. Padding is non-deterministic (random bytes; not zero-filled —
   defends against length-equality attacks on the padding itself).

### 4.2 `EnvelopeRoundTripTests.swift` (NEW, ≥ 4 specs)

1. Encrypt + pack → unpack + decrypt with two devices in the recipient
   list → both recover plaintext.
2. Tampered ciphertext byte → decrypt raises.
3. Tampered envelope header → unpack raises.
4. Envelope addressed only to peer (own-device missing) → own-device
   decrypt raises `noSlotForThisDevice`.

### 4.3 `KeyRegistrationFlowTests.swift` (NEW, ≥ 4 specs)

1. First pairing posts to `/me/devices`, `/me/prekeys/signed`,
   `/me/prekeys/one-time` in that order.
2. The private identity key never appears in any `URLRequest` body
   (Keychain-only; pinned by inspecting recorded URLProtocol calls).
3. Refill triggers when `X-Prekey-Low-Water: true` response header
   arrives.
4. Revoke calls `DELETE /me/devices/<id>` and clears the local
   `KeychainIdentityStore`.

### 4.4 `DowngradeFailClosedTests.swift` (NEW, ≥ 3 specs)

1. Backend responds `protocol: "plain"` to a `["e2e_v1"]` request →
   `startE2eConversation` throws `ProtocolDowngradeError`.
2. The UI shows the warning sheet (snapshot test).
3. No message is sent on the downgraded conversation (mocked api
   asserts no `POST /messages`).

### 4.5 `OwnDeviceDecryptTests.swift` (NEW, ≥ 2 specs)

1. Sender on device A posts a message → device B (same user) fetches
   `/messages` → can decrypt.
2. Sender on device A → device A re-fetches `/messages` → can decrypt.

### 4.6 `ComposerPrecheckTests.swift` (NEW, ≥ 3 specs)

1. Peer has ≥ 1 active device key → composer enabled.
2. Peer has zero active device keys → composer shows the hint + disabled.
3. `/capabilities?me=true` failing transiently → optimistic enable +
   surface the error.

### 4.7 `KeychainStorageClassTests.swift` (NEW, ≥ 2 specs)

1. Identity key has class
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
2. Querying after a simulated device-lock does not yield the key
   (sanity check on the protection class — only relevant on device,
   skipped on the simulator unless the project's
   `--enable-keychain-restrictions` flag is set in CI).

### 4.8 `BiometricPairingTests.swift` (NEW, ≥ 4 specs)

1. `test_default_pairing_creates_both_keychain_entries` — biometric
   primary + passphrase fallback. Both Keychain items hold the same
   wrapped KEK (compared after manual unwrap with the fallback secret).
2. `test_power_user_pairing_skips_biometric_entry` — "Use passphrase
   only" mode creates only the fallback Keychain entry; querying the
   biometric class returns `errSecItemNotFound`.
3. `test_biometric_reset_invalidates_primary_recovered_via_fallback` —
   simulate `BiometryCurrentSet` change (passcode reset); primary
   Keychain entry returns `errSecItemNotFound`; fallback unwrap with
   the passphrase recovers the same KEK.
4. `test_fallback_passphrase_argon2id_parameters_match_web` — verify
   the Argon2id parameters (64 MB memory, 3 iterations) match the
   web KEK derivation. Pins the cross-client decision (one wrap, two
   clients).

### 4.9 `ReceiptDotsTests.swift` (NEW, ≥ 5 specs)

1. `test_zero_dots_when_neither_set` — `delivered_at == nil` and
   `read_at == nil` → no dots rendered.
2. `test_one_dot_when_delivered_not_read` — `delivered_at != nil`,
   `read_at == nil` → one dot.
3. `test_two_dots_when_read` — `read_at != nil` → two dots
   (regardless of `delivered_at` — the schema CHECK guarantees
   `read_at` only set after `delivered_at`).
4. `test_no_dots_on_incoming_messages` — receipts render only on
   outgoing bubbles (sender == current user).
5. `test_mark_read_debounce_250ms` — a bubble that scrolls into
   view + out within 100 ms does NOT call
   `POST /messages/<id>/read`; staying on screen ≥ 250 ms triggers
   one POST. Idempotency: a second triggering of the same message
   doesn't POST again in the same VM lifetime.

### 4.10 `DisableRestoresPlainTests.swift` (NEW, ≥ 2 specs) — opt-out guard

1. Boot the host app with `meinchat-plus` disabled in the bundled
   `plugins.json` → meinchat behaves exactly as in the 1.0 release
   (XCTAssertEqual of a baseline snapshot of the meinchat tab tree).
2. Enable, send an E2E message, disable → subsequent reads in plain
   conversations are unaffected; the e2e_v1 conversations show a
   `disabled` state instead of crashing.

## 5. Acceptance

- `swift test` GREEN on the new package.
- Host app builds GREEN with `meinchat-plus` both **enabled** (the v1
  launch default) and **disabled** (the user-opt-out path).
- Two-user round-trip: web (S28.3b §3) ↔ iOS (this sprint), both on
  the same backend, exchange E2E messages. `tcpdump`-on-loopback shows
  ciphertext only; the database `body` column is NULL for the rows;
  the `envelope` column does NOT contain the plaintext marker.
- A clean install with `meinchat-plus` **disabled** runs every
  pre-existing UITest GREEN — pinned by `DisableRestoresPlainTests`.
- v1-launch build (`MARKETING_VERSION 1.1`,
  `CURRENT_PROJECT_VERSION 2`) ships with `meinchat-plus` listed in
  the bundled `plugins.json` as `enabled: true` — default-on per
  S28 decision R2-Q1.
- A new device pairing → 100 one-time prekeys land server-side
  (verified via `SELECT count(*) FROM meinchat_plus_one_time_prekey
  WHERE device_id = …`).
- Concurrent two-senders-to-same-offline-recipient scenario consumes
  two distinct one-time prekeys (closes the backend race spec from
  S28.3b §2.10; verified by the integration test there).
- Settings shows "1 active device, 97 of 100 one-time prekeys
  remaining" after three messages.
- **Biometric pairing (default path):** after first launch + Face ID /
  Touch ID consent, the user sends a message without entering a
  passphrase. Quitting + relaunching the app re-prompts biometrics
  before the first send (per `kSecAccessControlBiometryCurrentSet`).
- **Passphrase fallback path:** simulate biometric reset (`xcrun
  simctl …` on simulator; passcode change on device) → the next
  send prompts for the recovery passphrase; correct passphrase
  recovers the KEK; messages send normally; the biometric Keychain
  entry is re-sealed on the next biometric consent.
- **Receipt UI live check:**
  - Send a message from device A to device B (different user) →
    bubble on A shows zero dots until B's client fetches; one dot
    after fetch; two dots after B's UI marks read.
  - Receipts work identically in plain conversations (verified by a
    plain-mode subscriber test).
  - Receipt dots are NEVER rendered on incoming bubbles.
- **Disabling meinchat-plus via Settings** restores plain meinchat
  cleanly — no orphaned tables blocking re-enable later (migration
  up-down-up oracle on the backend; UI snapshot test on iOS).

## 6. Out of scope

- **Group chats.** Sender Keys layer is a future sprint.
- **Cross-device history transfer / recovery codes.** New devices read
  only ciphertext addressed to their brand-new key.
- **macOS / Mac Catalyst client.** Inherits the same plugin trivially;
  separate sprint when needed.
- **Push notifications for E2E messages.** A future
  `meinchat-push` plugin would register the dispatcher.
- **Custom keyboard / share-extension support.** Out of scope for v1.
- **Beta-RC promotion to GA.** This sprint ships the plugin behind the
  opt-in flag; the GA flip happens in a separate release plan.

## 7. Engineering-requirements check

- **TDD-first:** ≥ 23 new specs land before the Signal client +
  plugin lifecycle bodies are written. The `DisableRestoresPlainTests`
  spec is the beta-RC safety net — pins meinchat-alone parity.
- **DevOps-first:** `swift test` runs offline against
  `URLProtocol` mocks; the round-trip happens in the host app's
  UITest target against a real backend with S28.3b + S28.6.
- **SOLID — S:** every Domain class has one job (pad, pack, send,
  read, downgrade-guard). No god `SignalService`.
- **SOLID — O:** the plugin extends meinchat via the existing
  `PlatformSDK.routeOverride(forProtocol:)` seam. No SDK change.
- **SOLID — L:** disabling the plugin restores meinchat-alone
  behaviour (verified by `DisableRestoresPlainTests`).
- **SOLID — D:** every collaborator (Keychain store, session store,
  prekey store, api, libsignal) is injected at `bootstrap`. No
  module-globals.
- **NO OVERENGINEERING — concrete corrections.**
  - **No new SDK extension point.** Existing `routeOverride` covers it.
  - **No `LibSignalClient` fork** — vendored verbatim.
  - **No background message-prefetch.** Existing polling covers it.
  - **No telemetry that defeats the operator-blind goal.** No on-device
    timing instrumentation that gets posted upstream.
  - **No second key store.** One Keychain entry, two consumers (cache
    seal + identity wrap) — same as S28.6 §7.
- **DRY — concrete corrections.**
  - **Shared Keychain KEK** with S28.6's `MessageCache`. One
    Argon2id stretch, two homes — cache seal + identity wrap.
  - **One `EnvelopePacker`** matches the server-side `cbor2` grammar
    AND the web client's `cbor-x` grammar — one wire-format home
    across three implementations.
  - **One `DowngradeGuard`** is the single home for the
    `accepted_protocols=["e2e_v1"]` → response-check pattern; called
    from both `SecureSendService.startE2eConversation` and the
    composer precheck.
- **Beta-RC safety:** brand-new package, disabled by default, no
  host-shell change, no `VBWDCore` change. Revertible cleanly in
  TestFlight by flipping the bundled `plugins.json` entry.
- **Core agnostic:** the iOS host app shell is untouched.

---

## Anchor

Inherits the binding engineering requirements at
[`_engineering_requirements.md`](_engineering_requirements.md) (which
chains back to `../../20260525/sprints/_engineering-requirements.md`
and `../../20260519/sprints/_engineering-requirements.md`).
