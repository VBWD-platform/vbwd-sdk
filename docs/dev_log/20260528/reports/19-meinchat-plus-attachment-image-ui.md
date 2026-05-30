# Report 19 — meinchat-plus attachment image UI (e2e images end-to-end)

**Date:** 2026-05-30
**Sprint:** [S28.4](../done/s28-4-attachment-encryption.md) §3.
**Follow-up to:** [report 18](18-meinchat-plus-view-wiring.md).
**Gates:** fe-user meinchat + meinchat-plus **151 vitest specs** GREEN, eslint
clean. **Commits/pushes:** none (deferred per user).

The final vertical slice: send + render encrypted images in the UI.

## Key correctness decision — ordering under the in-order ratchet

Attachment keys are ratchet-wrapped, so **each attachment is a ratchet message
that must be decrypted in order** — a lazy "decrypt on render" would desync the
in-order ratchet. So:
- **v1 uploads fullres only** (one ratchet message per image — no thumb to skip).
- The store decrypts the **text envelope THEN the attachment, in order**, during
  hydration (`provider.hydrateRow`), not lazily on render.

## Provider (`src/provider.ts`)

- **`sendEncryptedImage(conv, peer, file, caption)`** — `processImage` (injectable;
  canvas default in `src/image.ts`, raw-bytes fallback) → send the e2e caption
  message → `encryptAttachment` the fullres blob + `uploadAttachment`. Returns a
  row whose attachment carries the `envelope_header` + a **local `blob:` preview**
  (the sender can't decrypt its own ciphertext — no self-slot).
- **`hydrateRow(row)`** — `resolveInbound` (shared with `decryptRow`) → decrypt
  the text slot, then each e2e attachment in order → `{body, attachmentUrls}`
  (attachment id → `blob:` URL). Never throws.
- Constructor gains `deps: { attachmentApi, processImage }`; `pairing.ts` wires
  the real `uploadAttachment`/`downloadAttachment`.

## Store (`useMeinchatStore`)

- `sendAttachment` routes `e2e_v1` conversations through
  `provider.sendEncryptedImage` (fail-closed if unsupported); plain unchanged.
- `_hydrateE2eRows` / `_decryptInPlace` use `provider.hydrateRow` (text + image),
  falling back to `decryptRow` on a text-only provider. `MessageRow.attachmentUrls`
  added.

## MessageBubble

- The fullres image renders from the storage URL for `plain` and from
  `message.attachmentUrls[att.id]` (the decrypted `blob:` URL) for `e2e_v1`
  (null until hydrated → no broken image).

## Tests (added; 151 total)

- Provider e2e image round-trip (send → hydrate recovers caption + `blob:` URL,
  in order) + text-only `hydrateRow`.
- Store: e2e image routes to `sendEncryptedImage`; fail-closed without a provider;
  `hydrateRow` sets body + attachmentUrls on read.
- MessageBubble: e2e attachment renders from the decrypted blob URL; renders
  nothing before decryption.

## Status — meinchat-plus web client is feature-complete

Text **and** image E2E now work end-to-end through the UI: pair via the gate →
send encrypted text/images → both decrypt + render. Remaining is **hardening**
only (ratchet skipped-message-key cache — which would also re-enable e2e
thumbnails; crypto audit; signed-prekey rotation / multi-device) and the **git
push** of the 3 repos (deferred). iOS is the separate app.
