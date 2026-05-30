# Report 17 — meinchat-plus Vue glue (pairing UI + precheck + attachment transport)

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3.3/§3.7 +
[S28.4](../done/s28-4-attachment-encryption.md) §3.
**Follow-up to:** [report 16](16-meinchat-plus-pairing-flow.md).
**Gates:** fe-user meinchat + meinchat-plus **136 vitest specs** GREEN, eslint
clean. **Commits/pushes:** none (deferred per user).

The reusable, tested Vue building blocks that the meinchat views mount.

## Pairing UI

- **`composables/usePairing.ts`** — reactive state machine (`unknown` →
  `unpaired`/`locked` → `ready`) over `pairNewDevice`/`unlockDevice`/`isPaired`:
  `refresh`, `pair`, `unlock`, `lock`, `saveSessions`, `error`, `busy`. Wrong
  passphrase surfaces an error (no throw). **6 specs.**
- **`components/PairingSheet.vue`** — presentational passphrase prompt
  (set-vs-unlock title, busy/error states), emits `submit(passphrase)`; the view
  wires it to `usePairing`. **5 mount specs** (titles, emit on submit, disabled
  while busy, error display, no-emit on empty). Locale strings added.

## Composer precheck

- **`composables/useComposerPrecheck.ts`** — reactive wrapper over
  `precheckPeerSecureChat` (`canSend`, `hint`, `checking`, `check()`). **2 specs.**

## Attachment transport

- **`api.ts`** — `uploadAttachment` (`POST /messages/<id>/attachments`) +
  `downloadAttachment` (`GET /attachments/<id>` → bytes).
- **`attachment-transport.ts`** — `encryptAndUploadAttachment` (hybrid encrypt →
  POST opaque blob + envelope_header) + `downloadAndDecryptAttachment` (GET blob
  → unwrap own key → decrypt). **1 round-trip spec** (encrypt+upload →
  download+decrypt recovers the image, with the server storing the blob verbatim).

All exported from `index.ts`.

## What remains — app-level view wiring only

The crypto, session, persistence, pairing, precheck, and attachment-transport
LOGIC are complete + tested. The last step is mounting them in the **meinchat**
plugin's existing UI (modifying its views):
- Gate `ConversationView` on `usePairing` (show `PairingSheet` until `ready`);
  call `saveSessions()` after send / on visibility-change.
- Bind the composer Send button to `useComposerPrecheck`.
- Wire the image picker → `encryptAndUploadAttachment` (after the e2e message is
  created) and render via `downloadAndDecryptAttachment` (→ `blob:` URL) in
  `MessageBubble`.

Plus hardening (ratchet skipped-key cache, crypto audit, signed-prekey rotation /
multi-device) and the git push of the 3 repos (deferred).
