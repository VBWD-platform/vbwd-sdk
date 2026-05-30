# Report 13 — meinchat-plus standalone repos + fe-user client crypto (S28.4 incr 5)

**Date:** 2026-05-29
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3 (web client) + the
"plugins live in their own repos" rule.
**Decisions this session:** repos **private for now** (diverges from the locked
"public from day one" until crypto is audit-ready); **iOS not built** (developed
in the separate iOS app).
**Commits/pushes:** **none** — git seeding/pushing deferred per user. The 3
GitHub repos were created (empty); all plugin code lives on disk in the SDK
workspace dirs.

## Repos created (private, VBWD-platform)

- `vbwd-plugin-meinchat-plus` (backend)
- `vbwd-fe-user-plugin-meinchat-plus` (web client crypto)
- `vbwd-fe-admin-plugin-meinchat-plus` (admin device-key view)

## Backend extraction — prepped (push deferred)

`vbwd-backend/plugins/meinchat_plus/` (the tested S28.3b/S28.4 code) got a
`.gitignore` + `README.md`. The `git init` in-place / commit / push to
`vbwd-plugin-meinchat-plus` is **deferred** (user interrupted the push). The
dir is gitignored by the parent SDK, mirroring how `plugins/meinchat` is itself
a nested clone — so it can be `git init`-ed in place when ready without
disturbing the running stack.

## fe-user crypto plugin — BUILT + tested (26 specs green, lint clean)

`vbwd-fe-user/plugins/meinchat-plus/`. **Library reality:**
`@signalapp/libsignal-client` is a **Node-native** addon and does **not** run in
a browser, so the implementation uses audited pure-JS primitives — `@noble/curves`
(X25519/Ed25519), `@noble/ciphers` (ChaCha20-Poly1305), `@noble/hashes`
(HKDF/HMAC-SHA256), `hash-wasm` (Argon2id), `cbor-x` (added to fe-user
`package.json`; pure-JS, no native binaries).

`src/crypto/`:
- **`keys.ts`** — device identity = one Ed25519 key (registered server-side +
  verified for signed prekeys) projected to X25519 (Montgomery) for ECDH —
  Signal's "one identity key, two uses"; signed/one-time prekeys; AEAD seal/open.
- **`x3dh.ts`** — X3DH agreement (initiator + responder derive the same SK; test
  asserts equality).
- **`ratchet.ts`** — Double Ratchet (DH + symmetric KDF chains) → per-message
  forward secrecy; header bound into AEAD AD. *v1 limitation: in-order only (no
  skipped-key cache) — documented + flagged for the deferred crypto audit.*
- **`messaging.ts`** — send (256-pad → per-device fan-out → CBOR envelope
  matching the server `SignalEnvelopeValidator`) + read (own-slot decrypt).
- **`padding.ts`** (256-byte length-hiding) · **`kek.ts`** (Argon2id passphrase
  KEK + wrap/unwrap — the swap point meinchat S28.2 `loadKek` left open).
- **`downgrade.ts`** (fail-closed) · **`registration.ts`** + **`api.ts`** (generate
  + upload public material; device/prekey/bundle + e2e message endpoints) ·
  **`base64.ts`** · plugin `index.ts` + config/admin-config/locales/README.

**26 vitest specs:** padding (5), identity/Montgomery consistency (2), X3DH +
Double Ratchet round-trip + forward secrecy + ciphertext/header tamper + wrong-key
(7), two-device fan-out + own-device decrypt + length-hiding (4), KEK wrap/unwrap
(3), downgrade fail-closed (3), key registration + refill (2). `eslint` clean.

**Not yet wired (follow-up):** the `useMeinchatStore` send/read override (needs a
crypto-provider seam in the meinchat plugin store) + composer-precheck component
+ attachment encrypt/decrypt UI. The crypto API is exported from `index.ts` ready
for that wiring. A cross-language JS↔Python e2e is future; the server contract is
already proven by the backend round-trip specs.

## fe-admin plugin — scaffolded + tested (3 specs, lint clean)

`vbwd-fe-admin/plugins/meinchat-plus/` — deliberately thin (E2E → no content
inspector). One route `/admin/meinchat-plus/devices` (gated by
`meinchat.conversations.inspect`) listing a user's public device keys + an
"encrypted, not inspectable" notice.

## Recipes wired

`ci-status.sh` EXPECTED list + `push-plugins.sh` (backend underscore→dash
mapping `meinchat_plus:meinchat-plus`; fe-user + fe-admin `meinchat-plus` slugs)
updated for the 3 new repos. `bash -n` clean.

## Remaining

- Git seed + push the 3 repos (user-gated): `git init` in each plugin dir, commit,
  push. (Backend prep done; fe dirs ready.)
- Wire the fe-user crypto into the meinchat store + UI (needs the store seam) +
  composer precheck + attachment encrypt/decrypt.
- Crypto audit (esp. the in-order ratchet → skipped-key cache) + flip repos public.
- iOS: handled in the separate iOS app (not here). iOS must read `attachments[]`
  (the backend dropped `attachment_url`).
