# Report 14 — wiring the meinchat-plus crypto into the meinchat store

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3 (web client).
**Follow-up to:** [report 13](13-meinchat-plus-repos-and-fe-user-crypto.md) (crypto core).
**Gates:** backend meinchat `--full` GREEN · meinchat_plus `--full` GREEN ·
fe-user meinchat + meinchat-plus **102 vitest specs** GREEN, eslint clean.
**Commits/pushes:** none (deferred per user).

## The seam (core agnostic; gnostic in the plugin)

The meinchat base plugin owns the store + UI and knows nothing about crypto;
meinchat-plus registers a provider. Mirrors the backend port-registry pattern.

- **`meinchat/src/crypto/messageCryptoRegistry.ts`** — `MessageCryptoProvider`
  (`sendEncryptedText`, `decryptRow`) + `register/unregister/getMessageCrypto`.

## Backend (additive)

- `_serialize_conversation_for_user` now emits `protocol`, so the client can
  tell which conversations are `e2e_v1` and route them. meinchat `--full` green.

## meinchat store (`useMeinchatStore`)

- `ConversationRow.protocol` + `MessageRow.protocol`/`envelope` added.
- **`sendText`** routes `e2e_v1` conversations through
  `provider.sendEncryptedText(...)` (client-encrypts + posts the envelope) and
  re-attaches the plaintext to the returned row for display; plaintext
  conversations are unchanged. **Fail-closed:** an `e2e_v1` send with no
  provider registered throws (never posts plaintext to an e2e conversation).
- **`_hydrateE2eRows`** decrypts `e2e_v1` rows into a display `body` on
  `openConversation` / `fetchMessages`; **`_decryptInPlace`** does the same for
  SSE-delivered rows in `handleStreamEvent`. Plaintext rows and the no-provider
  case pass through untouched; decryption never throws.
- 5 store-seam specs (e2e routes via provider; plain via the plaintext API;
  fail-closed without a provider; decrypt-on-read; plaintext untouched). The 17
  pre-existing store specs still pass.

## meinchat-plus provider

- **`src/provider.ts`** `MeinchatPlusProvider` implements the seam interface
  over the audited crypto: `sendEncryptedText` discovers addressed devices
  (peer + sender's own, minus the sending device), fans out via per-device
  ratchet sessions, packs the CBOR envelope, posts; `decryptRow` finds this
  device's slot and tries the sender's device sessions (returns null, never
  throws, if none decrypts). `SessionStore` abstracts session lifecycle.
- **`src/uuid.ts`** — UUID ↔ 16-byte (the envelope's device-id form).
- **`index.ts` `registerCryptoProvider(self, api, sessions)`** — the single hook
  the pairing flow calls to register the provider into the meinchat seam;
  `deactivate` unregisters.
- 3 specs: full Alice↔Bob provider round-trip with **real crypto** (encrypt +
  post → decrypt the same plaintext), null-on-no-session, and
  `registerCryptoProvider` populating the meinchat seam.

## Remaining (documented boundary)

The **`SessionStore` implementation** is the last layer: `ensureOutbound`
(X3DH-from-bundle over `getPrekeyBundle`) is straightforward, but full
**responder cold-start** (a prekey-message carrying the initiator's X3DH
material), **IndexedDB session persistence** (under the Argon2id KEK), and
**multi-device session routing** are a focused follow-up. The provider is
transport-correct and unit-tested against an injected store, so this is
localized to the store impl + a small envelope/prekey-message extension. Also
still pending: composer precheck UI, attachment encrypt/decrypt UI, the
in-order→skipped-key-cache ratchet upgrade + crypto audit, and the git push of
the 3 repos (all deferred).
