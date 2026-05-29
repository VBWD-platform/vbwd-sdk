# S28.2 — Client local cache with 10-day TTL (web IndexedDB + iOS CoreData) + shorten-only UI

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb the
critical review:
- §1 said "cache holds decrypted bodies"; §5 said "no plaintext at rest".
  Contradiction resolved → **cache holds decrypted bodies, but the
  storage backend is wrapped under a per-device KEK** (WebCrypto-wrapped
  IDB rows on web; Keychain-protected CoreData store on iOS).
- "shorten-only client retention" relabelled honestly as **best-effort
  default** — a forked or hostile client can ignore it; it is not a
  security guarantee.
- Cache eviction now runs when **either** the user-set TTL or the
  server-suggested TTL is reached, whichever is shorter.
**Depends on:** [S28.0](s28-0-config-and-limits-endpoint.md) (reads `messages_retention_days_client_suggested`).
**Blocks:** nothing directly; works for both plaintext (today) and ciphertext (after S28.3b).

**Repos touched:** `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** fe-user `npm run lint && npm run test` GREEN on the plugin; iOS `swift test` GREEN on the package.

---

## 1. Goal

Both clients keep a persistent local copy of messages for up to **10
days** (configurable via the server's suggested value, shorten-only
**best-effort**). Cold-start of a conversation reads the local cache
first, then fetches the server's most-recent window to fill gaps + pick
up new arrivals.

Decouples client history from the server's intentional amnesia
(2-day prune from S28.1). The cache holds **decrypted body strings**
(so the conversation paints instantly on cold-start); the **storage
backend is wrapped under a device-bound KEK**:
- **Web:** IndexedDB rows are AES-GCM-encrypted client-side under a
  WebCrypto key derived from the device-pairing passphrase (Argon2id;
  see S28.3b §3.2). The KEK is cached in `sessionStorage` for the tab
  session so per-read cost is one decrypt only.
- **iOS:** the CoreData SQLite file is protected by NSFileProtection
  (`completeUntilFirstUserAuthentication`) and the row payload column
  is sealed under a Keychain-stored AES-GCM key
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).

What this DOES guarantee (corrects critical-review §C16):
- A device-OS-level adversary with only filesystem access cannot read
  cached bodies — they need the KEK, which is gated by the OS
  (passphrase + Keychain class).
- The wire stays ciphertext post-S28.3b; only the **owner's own
  decrypted view** is cached.

What this does NOT guarantee:
- A malicious OS-level read with full memory access can recover the
  KEK at use time. Out of scope.
- "Shorten-only client retention" is enforced by **well-behaved
  clients only**. A forked client can keep messages longer; the server
  has no compelling vote. This is honestly a UX default, not a
  security control.

## 2. Web (`vbwd-fe-user/plugins/meinchat`)

### 2.1 New IndexedDB store — encrypted at rest

`src/composables/useLocalMessageCache.ts`:

```ts
interface CachedMessageEnvelope {
  conversation_id: string;
  message_id: string;
  // AES-GCM-256 sealed payload of the decrypted message JSON. The
  // payload includes body, sender, sent_at, cached_at. Nothing
  // searchable lives outside the seal — even sender nicknames are
  // inside the payload.
  iv: Uint8Array;             // 12 bytes
  ciphertext: Uint8Array;     // sealed JSON
  cached_at: number;          // unix ms — outside the seal so the
                              // eviction sweep doesn't have to decrypt
                              // every row
}

export function useLocalMessageCache(kek: CryptoKey /* DI'd at boot */) {
  return {
    async putMany(rows: MessageRow[]): Promise<void>,             // seals each row
    async listByConversation(id: string, limit?: number): Promise<MessageRow[]>,  // opens each row
    async removeByConversation(id: string): Promise<void>,
    async evictOlderThan(ms: number): Promise<number>,            // reads cached_at only — no decrypt
  };
}
```

Backed by `idb` (≤ 8 kB minified, audited). Object store keyed by
`(conversation_id, message_id)` with an index on `cached_at` for the
eviction sweep.

**KEK derivation (DI'd, not held module-global):**
- At first plugin boot, the user is prompted for a passphrase (the
  same one S28.3b §3.2 uses for the device private key).
- Argon2id-stretches into a 256-bit KEK; cached in `sessionStorage`
  (per-tab, cleared on close).
- The boot helper `await loadKek()` is the only path into
  `useLocalMessageCache(kek)` — there is no "unencrypted cache"
  fallback. Reconciliation of the earlier §1 vs §5 contradiction.

### 2.2 Eviction sweep

`src/workers/cache-evict.ts` — Web Worker, registered from
`useMeinchatStore.boot()`. Runs every 30 minutes (`setInterval`) and
calls `evictOlderThan(now - clientRetentionDays * 86_400_000)`. The
retention value comes from `useMessagingLimits.data.messages_retention_days_client_suggested`,
clamped to the user's own setting (shorten-only).

### 2.3 Store integration

`useMeinchatStore.openConversation(nickname)` is reordered:
1. Resolve conversation id (existing).
2. `listByConversation(id)` from the local cache → populate
   `messagesByConv[id]` *immediately*.
3. Fetch the server's most-recent window via the existing route → merge
   by id (existing dedup logic in `sendText`/`handleStreamEvent` covers
   the merge case).
4. `putMany(server_rows)` to refresh the cache with the latest server
   state.

Net effect: user sees their history without waiting for a server round-trip.

### 2.4 Profile setting — shorten-only

In the existing `MeinchatRetentionSection.vue` (from S28.0), add a
numeric input below the read-only sentence: *"Keep on this device for
[N] days"*. Constraints:

- `min=0`, `max=server_suggested`, `step=1`.
- Disabled state when typing > server-suggested (HTML5 `max` does this
  natively).
- Persists in `localStorage` under `meinchat.client_retention_days`.
- Eviction sweep reads this user-setting if present, else falls back to
  the server-suggested.

### 2.5 Tests

#### `plugins/meinchat/tests/unit/composables/use-local-message-cache.spec.ts` (NEW, ≥ 6 specs)

Uses `fake-indexeddb` (already an fe-user test dep). All specs run
against the real IDB API.

| # | Spec |
|---|---|
| 1 | `putMany` writes rows; `listByConversation` reads them back in `sent_at` order |
| 2 | Two `putMany` for the same id → last write wins (idempotent merge) |
| 3 | `evictOlderThan(threshold)` removes only rows with `cached_at < threshold` |
| 4 | Eviction returns the deleted count |
| 5 | `removeByConversation` deletes only that conversation's rows |
| 6 | DB upgrade path: opening a v2 schema over an existing v1 DB does not drop data |

#### `plugins/meinchat/tests/unit/stores/use-meinchat-store-with-cache.spec.ts` (extended)

≥ 3 new specs:
1. `openConversation` paints cached rows before the server response.
2. Server rows merge by id; duplicates are not added.
3. After a server fetch, `putMany` is called with the server's rows.

#### `plugins/meinchat/tests/unit/components/meinchat-retention-section.spec.ts` (extended from S28.0)

≥ 2 new specs:
1. The numeric input's `max` is bound to the server-suggested value.
2. Setting a value > server-suggested is rejected (the spec types a
   higher number via `fireEvent.input` and asserts the v-model stays
   clamped).

## 3. iOS (`vbwd-ios-plugin-meinchat`)

### 3.1 CoreData entity `CachedMessage` — sealed payload

In a new `.xcdatamodel`. The plaintext-bearing columns (body, sender
nickname, attachment URL, etc.) are NOT direct attributes — they're
sealed inside `payload`:

```
CachedMessage
  id: UUID (primary)
  conversationID: UUID (indexed)
  cachedAt: Date (indexed)                  # outside the seal — eviction sweeps read it
  iv: Data (12 bytes)
  payload: Data                             # AES-GCM-256 sealed JSON of MessageRow
```

The CoreData SQLite file uses `NSPersistentStoreFileProtectionKey:
FileProtectionType.completeUntilFirstUserAuthentication`. The
AES-GCM-256 key lives in Keychain under
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; loaded into a
`SymmetricKey` at `MeinChatPlugin.bootstrap()` and DI'd into
`MessageCacheProtocol` implementations. Reconciles §1 vs §5.

### 3.2 `MessageCache` service

`Sources/MeinChatPlugin/Domain/MessageCache.swift`:

```swift
public protocol MessageCacheProtocol {
    func upsert(_ rows: [MessageRow]) async throws
    func list(conversationID: UUID, limit: Int?) async throws -> [MessageRow]
    func remove(conversationID: UUID) async throws
    @discardableResult
    func evict(olderThan: Date) async throws -> Int
}
```

### 3.3 Background prune

Registered as a `BGAppRefreshTask` via `BGTaskScheduler`. Runs at app
launch (best-effort) + every 24 h while resident. Reads the user's
chosen retention (in `UserDefaults`) clamped to the server-suggested
value.

### 3.4 Conversation VM integration

`ConversationViewModel.load()` mirrors the web change: cache-first,
then server fetch + upsert.

### 3.5 Settings row

Add a stepper to the existing Meinchat settings section:

> *"Keep on this device for [10] days"* — stepper bound to the
> server-suggested as max.

### 3.6 Tests — `Tests/MeinChatPluginTests/MessageCacheTests.swift` (NEW, ≥ 6 specs)

| # | Spec |
|---|---|
| 1 | `upsert + list` round-trip |
| 2 | `upsert` is idempotent on same id |
| 3 | `list` orders by `sentAt` ascending |
| 4 | `evict(olderThan:)` removes only matching rows |
| 5 | `remove(conversationID:)` scoped delete |
| 6 | Background task respects the user-chosen `clamp(min: 0, max: serverSuggested)` |

Plus extend `ConversationViewModelTests` with one spec asserting cache-first paint.

## 4. Acceptance criteria

- Send 5 messages on web → close tab → reopen the conversation → all 5
  visible *before* the server responds (verified by network throttle).
- Same on iOS (force-quit, reopen, observe cache paint).
- Backdate a cached row by 11 days → next eviction tick removes it
  (verified by unit spec + manual check).
- Settings stepper / numeric input clamps to `[0, server_suggested]`
  in both clients (best-effort UX default, not a security control).
- **At-rest encryption check (corrects critical-review §C16):** raw
  filesystem read of the IDB blob (web) or the CoreData SQLite file
  (iOS) does NOT contain the plaintext body bytes of any cached row.
  Pinned by unit specs that read the raw storage and grep for a known
  plaintext marker — must be absent.
- **No KEK leak through `localStorage`** — the only persistent storage
  on web is IDB; the KEK is `sessionStorage` only. Pinned by a unit
  spec.
- **iOS Keychain class is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`**
  for the symmetric key (verified via a unit spec that queries
  Keychain attributes).
- fe-user + iOS test suites GREEN.

## 5. Out of scope

- **End-to-end encrypted cache rows.** Cache stores whatever the wire
  carries — plaintext today, ciphertext after S28.3b decrypts on the
  way *into* the cache. No special handling in this slice.
- **Cache import/export across devices.** A device only knows what it
  received. Cross-device sync is a meinchat-plus follow-up.
- **Persistent ratchet state on the client.** That's S28.3b's
  responsibility (and it has its own crypto-state schema).

## 6. Engineering-requirements check

- **TDD-first:** ≥ 20 new client specs (was 16; added the at-rest
  encryption pins) land before the cache logic is written.
- **SOLID — S:** the cache has one job (persist messages + age them
  out). It is NOT the source of truth (server is).
- **SOLID — L:** `MessageCacheProtocol` is substitutable — a no-op
  in-memory impl can be injected for tests without changing call sites.
- **SOLID — D:** the cache + KEK are injected into the store;
  ConversationVM on iOS receives it via init.
- **NO OVERENGINEERING — concrete corrections in this revision.**
  - **No second eviction strategy.** TTL only — no LRU, no quota, no
    background sync protocol.
  - **No SQLCipher dependency on iOS.** NSFileProtection + Keychain
    key + sealed payload column is enough; a full SQLCipher dependency
    is heavier than the threat model warrants here.
  - **No web fallback to LocalStorage** for the KEK. SessionStorage
    only — the earlier draft mentioned "encrypted-at-rest LocalStorage"
    as a fallback, but introducing a second persistence surface (with
    its own threat model) doubles the audit surface for marginal UX
    benefit.
  - **No per-conversation key derivation.** One per-device KEK seals
    every row — simpler invariant. (A per-conversation key would buy
    little: an attacker with the device KEK can grind through all
    conversations anyway.)
- **DRY — concrete corrections.**
  - **Same KEK on web** powers the device private key wrap (S28.3b
    §3.2) AND the cache seal — one passphrase, one Argon2 stretch,
    two consumers.
  - **One retention-resolver helper per client** answers
    "current eviction TTL = min(user_setting, server_suggested)"
    for both the sweep and the settings UI.
- **Liskov on the wire:** the cache stores a sealed `MessageRow`
  exactly (the unsealed contents are identical); nothing about the
  server-side contract changes.
