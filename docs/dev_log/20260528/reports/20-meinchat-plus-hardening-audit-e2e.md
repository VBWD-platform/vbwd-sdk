# Report 20 — meinchat-plus hardening: skipped-key cache, thumbnails, SPK rotation, crypto audit, e2e smoke

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3 + [S28.4](../done/s28-4-attachment-encryption.md) §3.
**Follow-up to:** [report 19](19-meinchat-plus-attachment-image-ui.md).
**Gates:** fe-user meinchat + meinchat-plus **156 vitest specs** GREEN, eslint
clean, **meinchat-plus vue-tsc clean** (project-wide tsc still red on pre-existing
payment-plugin errors — out of scope). **Commits/pushes:** none (deferred per user).

The "outstanding hardening + ops" list from report 19, cleared. This is the last
engineering gate before the 3 repos can be flipped public (which itself still
waits on an *independent* crypto review — see the audit doc).

## 1. Ratchet skipped-message-key cache (Signal MKSKIPPED) — `crypto/ratchet.ts`

The v1 ratchet was in-order only; out-of-order / skipped delivery threw. Added the
standard Signal skipped-key store:
- `RatchetState.skipped: Map<base64(ratchetPub):n → messageKey>` (serialized in
  `crypto/serialize.ts` as a base64 record).
- `trySkippedMessageKey` (pop + single-use delete) tried first on decrypt;
  `skipMessageKeys` advances the receive chain to a target index, caching each
  key it passes. `ratchetDecrypt` rewritten: skipped-key → DH-ratchet (skipping
  the previous chain's tail via `header.pn`) → skip within the new chain → decrypt.
- Bounded by `MAX_SKIP = 1000`: a header that would skip more is rejected (bounds
  memory + a malicious huge-`n`).
- Tests (`crypto/skipped-keys.spec.ts`, 4): out-of-order within a chain,
  out-of-order across a DH-ratchet step, single-use replay rejection, MAX_SKIP guard.

## 2. E2E thumbnails re-enabled — `src/provider.ts`

Report 19 shipped fullres-only because a second ratchet-wrapped attachment key
would have desynced the in-order ratchet. The skipped-key cache removes that
constraint, so `sendEncryptedImage` now uploads **both** fullres + thumb (loop
over `['fullres','thumb']`), each a hybrid-encrypted blob + per-recipient wrapped
key, and `hydrateRow` decrypts both in order. Test asserts 2 uploads + both
`blob:` URLs hydrate.

## 3. Signed-prekey rotation — `src/session.ts`

`OwnDeviceMaterial` gains `previousSignedPrekeys?: KeyPair[]`. `establishInbound`
now matches an incoming X3DH `spk` against the **current OR any previous** signed
prekey, so a peer who fetched a now-rotated bundle can still cold-start a session
(otherwise their first message would be undecryptable across a rotation). Test
(`store/spk-rotation.spec.ts`): peer establishes with an old prekey the responder
has rotated past → still decrypts. **Note:** the swap accepts a rotated prekey but
there is no periodic local rotation *job* yet — flagged in the audit as an open item.

## 4. Multi-device — documented as a v1 limitation

Sends already fan out to every active peer + own device. There is no cross-device
session sync / sender-key group ratchet and no "verify your other device" flow;
new devices can't read history sent before they paired. Captured in the audit doc
§5 rather than built (no-overengineering).

## 5. Crypto audit — `plugins/meinchat-plus/docs/crypto-audit.md`

Implementer self-review (explicitly *not* an independent audit): primitives table,
the X3DH + Double Ratchet + hybrid-attachment construction, security properties
claimed, threat model (in/out of scope), and the **known limitations to clear
before public**. Headline gap flagged: **no identity-key verification UX (safety
numbers / TOFU pinning)** — without it, MITM resistance covers only a *prekey*
swap, not an identity-key lie by the server. README updated to point at it and to
drop the now-stale "in-order only" / "not yet wired" notes.

## 6. Playwright e2e smoke — `tests/e2e/prod-e2e.spec.ts`

Mirrors meinchat's env-gated `prod-chat.spec.ts`. Drives the real key-distribution
surface on a target host: manifest `meinchat-plus` enabled → register device →
upload signed prekey (Ed25519-signed) → upload one-time prekeys → fetch the
prekey-bundle and **verify the signature client-side** → create a conversation
with `accepted_protocols:['e2e_v1','plain']` and assert it negotiates `e2e_v1`
once both peers have a device. Key material is minted in-spec via `@noble/curves`;
credentials come from `VBWD_*` env (never hardcoded — the repo ships public).

## 7. Type-safety cleanup (surfaced by the first full `vue-tsc` over the plugin)

The provider used local `RowLike`/`RowAttachment` shapes that did not match the
meinchat `MessageRow`/`MessageAttachment` the store seam passes. Reworked:
- Send methods return the canonical **`MessageRow`** (filling `sender_nickname`,
  `bytes_count`, `width_px`, `height_px`).
- Read methods accept an **`InboundRow`** — an ISP subset *derived from*
  `MessageRow` (DRY) declaring exactly the fields the read path consumes — so both
  a full store row and a minimal test row satisfy it.
- Fixed `Blob`-part / Uint8Array typing, two implicit-return `beforeEach` hooks,
  and unused imports. meinchat-plus now passes `vue-tsc` with zero errors.

## Status

meinchat-plus web client is **feature-complete and hardened**. Remaining before
public: an **independent crypto review** + **identity-key verification UX**
(audit §5), then the deferred **git push** of the 3 repos. iOS is the separate app.
