# Report 15 — meinchat-plus SessionStore (the last crypto layer)

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3.
**Follow-up to:** [report 14](14-meinchat-store-crypto-wiring.md) (store wiring).
**Gates:** fe-user meinchat + meinchat-plus **111 vitest specs** GREEN, eslint
clean. **Commits/pushes:** none (deferred per user).

Closes the boundary flagged in report 14: full session establishment
(initiator + responder cold-start) + at-rest persistence.

## Prekey-message header extension (`crypto/ratchet.ts`)

`RatchetHeader` gains optional `x3dh` (`ik`, `ek`, `spk`, `otk?`) carried in the
FIRST message of a session so a responder with no session can cold-start.
`encodeHeader`/`decodeHeader` round-trip it; `ratchetEncrypt` accepts it; it is
bound into the AEAD AD (tampering fails decryption). Normal messages keep the
exact prior header bytes (no regression). +3 header specs.

## SessionManager (`src/session.ts`)

- **`ensureOutbound(deviceId)`** — fetch the peer device's prekey bundle, verify
  the signed-prekey signature (Ed25519), run X3DH initiator
  (`montgomeryPubFromEd25519` of the peer identity), `initAlice`, and record the
  X3DH init the first outbound message must carry.
- **`establishInbound(senderDeviceId, x3dh)`** — responder cold-start:
  match our signed prekey + the consumed one-time prekey by public key,
  `deriveResponderSecret`, `initBob`. Verified to derive the **same SK** as the
  initiator.
- `takePendingX3dh` (one-shot first-message material), `get`/`set`,
  `serializeAll`/`loadAll`.

## Provider cold-start (`src/provider.ts`, `crypto/messaging.ts`)

`messaging.ts` split into `readOwnSlot` (decode header WITHOUT decrypting) +
`decryptOwnSlot`; `encryptEnvelope` threads per-recipient `x3dh`. The provider:
attaches `takePendingX3dh` to the first message per device; on read, tries
existing sessions, else cold-starts from the slot header's `x3dh` (resolving the
sender device by matching `ik` to its public key). `src/uuid.ts` unchanged.

## Persistence (`crypto/serialize.ts`, `src/persistence.ts`)

- `serializeRatchet`/`deserializeRatchet` — JSON-safe (base64) ratchet state.
- `saveSessions`/`loadSessions` — the snapshot is **sealed under the Argon2id
  KEK** (AEAD) before it touches storage; wrong KEK → throws.
- `KeyValueStore` with `InMemoryKeyValueStore` (tests/SSR) +
  `createIdbKeyValueStore` (browser, lazy `idb` import).
- Exported from `index.ts` for the pairing flow.

## Tests (9 new; 38 meinchat-plus / 111 fe total)

- **cold-start (2):** full no-prior-session round-trip — Alice initiates, Bob
  cold-starts the responder from the prekey header, then bidirectional (Alice
  msg #2 reuses the session; Bob replies; Alice DH-ratchets + decrypts);
  bad-signature bundle rejected.
- **persistence (4):** deserialized state keeps decrypting; sealed KV
  save→reload decrypts the next message; wrong-KEK rejected; IndexedDB adapter
  round-trip (fake-indexeddb).
- **header (3):** plain + x3dh + otk-null round-trips.

## What's left for a complete client

The crypto + session layer is now end-to-end functional. Remaining is product
integration + hardening (not crypto-core):
- **Pairing flow** — generate/persist the device identity (under the KEK), call
  `registerThisDevice` + `registerCryptoProvider(self, api, new SessionManager(...))`
  with an `idb` KV; load sessions on unlock. (All pieces exist + are exported.)
- Composer precheck UI + attachment encrypt/decrypt UI.
- Ratchet is **in-order only** (no skipped-message-key cache) — the documented
  item for the crypto audit before flipping the repos public.
- Signed-prekey **rotation** on the responder (currently matches the current
  active one) + multi-device session routing polish.
- Git seed + push the 3 repos (deferred). iOS = separate app (reads `attachments[]`).
