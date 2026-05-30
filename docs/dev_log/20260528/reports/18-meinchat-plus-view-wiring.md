# Report 18 — meinchat-plus app-level view wiring (text E2E end-to-end)

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3.
**Follow-up to:** [report 17](17-meinchat-plus-vue-glue.md) (Vue building blocks).
**Gates:** fe-user meinchat + meinchat-plus **145 vitest specs** GREEN, eslint
clean. **Commits/pushes:** none (deferred per user).

Wires the meinchat-plus UI building blocks into meinchat's `ConversationView`,
**keeping meinchat standalone** — meinchat exposes UI seams; meinchat-plus fills
them (same pattern as the `messageCryptoRegistry`).

## meinchat UI seams (`src/ui/conversationExtensions.ts`)

- `registerConversationOverlay(component)` / `getConversationOverlay()` — a
  plugin component overlaid inside the conversation (bound `:conversation`).
- `registerComposerPrecheck(fn)` / `getComposerPrecheck()` — async
  `(conv) → {canSend, hint?}`.
- Both default to null → **meinchat-alone renders no overlay and never blocks
  the composer**. 3 registry specs.

## ConversationView wiring (additive, guarded)

- Tracks the `conversation` row; renders the registered overlay
  (`<component :is="overlayComponent" v-if="overlayComponent && conversation">`)
  above the composer.
- On open, runs the registered composer precheck → disables Send
  (`:disabled="sending || composerBlocked"`) + shows a hint; best-effort (never
  blocks on a precheck failure).

## meinchat-plus fills the seams

- **`SecureChatGate.vue`** — the overlay: for an `e2e_v1` conversation that
  isn't `ready`, it drives `usePairing` (passphrase prompt via `PairingSheet`;
  pair on first use, unlock on return) and persists ratchet sessions on tab-hide
  (`visibilitychange` → `saveSessions()`). Self-contained (builds its deps from
  the api module + `createIdbKeyValueStore`). 4 mount specs.
- **`index.ts` `activate()`** registers `SecureChatGate` as the overlay + a
  composer precheck (wraps `precheckPeerSecureChat`); `deactivate()` clears them.
  2 specs.

## What this completes

**Text E2E is now wired end-to-end:** open an `e2e_v1` conversation →
`SecureChatGate` prompts for the passphrase → `pairNewDevice`/`unlockDevice`
registers the crypto provider → `useMeinchatStore.sendText` encrypts + posts the
envelope → incoming rows decrypt into the bubble (`_hydrateE2eRows` /
`_decryptInPlace`). The composer disables Send for a peer with no device.

## Remaining

- **Attachment image UI** — the last vertical slice: `store.sendAttachment` must,
  for e2e conversations, resize client-side (server can't resize ciphertext) +
  `encryptAndUploadAttachment` both blobs; `MessageBubble` must
  `downloadAndDecryptAttachment` → `blob:` URL for e2e rows. (Crypto + transport
  are done + exported; this is store/composer/bubble integration.)
- Hardening: ratchet skipped-key cache, crypto audit, signed-prekey rotation /
  multi-device. Git push of the 3 repos (deferred).
