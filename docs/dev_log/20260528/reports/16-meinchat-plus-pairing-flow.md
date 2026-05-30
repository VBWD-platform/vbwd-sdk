# Report 16 — meinchat-plus pairing flow (E2E end-to-end)

**Date:** 2026-05-30
**Sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) §3.3.
**Follow-up to:** [report 15](15-meinchat-plus-session-store.md) (SessionStore).
**Gates:** fe-user meinchat + meinchat-plus **114 vitest specs** GREEN, eslint
clean. **Commits/pushes:** none (deferred per user).

This is the capstone: the flow that ties identity + KEK + registration +
sessions + the store provider together so secure chat works in the running app.

## Device-material persistence (`src/device-store.ts`)

The device PRIVATE material (identity Ed25519 + Montgomery X25519, signed
prekey, one-time prekeys, deviceId, userId) is serialized to JSON and **sealed
under the Argon2id KEK** before IndexedDB. The KEK **salt** is stored unsealed
(not secret; needed to re-derive the KEK on unlock). `isPaired`, `saveDevice`,
`loadDevice` (throws on a wrong KEK), `saveSalt`/`loadSalt`.

## Pairing orchestration (`src/pairing.ts`)

- **`pairNewDevice({kv, passphrase, userId, providerApi, bundleApi, label?, register?, kekParams?})`**
  — first pairing: derive the KEK from a fresh salt, generate + register the
  device keys (`registerThisDevice`, overridable), persist the device (sealed) +
  salt, build a `SessionManager`, and **register the crypto provider into the
  meinchat store seam**. Returns a `PairedSession` (`deviceId`, `sessions`,
  `saveSessions()`, `lock()`).
- **`unlockDevice({kv, passphrase, userId, providerApi, bundleApi, kekParams?})`**
  — returning user: re-derive the KEK from salt + passphrase, **unseal** the
  device (`WrongPassphraseError` on AEAD failure) + the persisted sessions,
  register the provider.
- `isPaired`, `NotPairedError`, `WrongPassphraseError`. `saveSessions()` snapshots
  ratchet state after activity; `lock()` unregisters the provider + zeroes the KEK.
- All exported from `index.ts`.

## Tests (3 new; 41 meinchat-plus / 114 fe total)

- pair → persist → provider registered in the seam → `lock` → **unlock with the
  passphrase** re-registers; `isPaired` reflects state.
- **wrong passphrase → `WrongPassphraseError`**.
- **full end-to-end:** pair Alice + Bob → Alice→Bob cold-start message decrypts →
  `saveSessions` + `lock` both → **`unlockDevice` both** → a follow-up
  Alice→Bob message decrypts on the reloaded sessions.

## State of the meinchat-plus web client

The crypto, session, persistence, and pairing layers are **complete and
end-to-end tested**. To go live the app needs only UI glue:
- A pairing UI (passphrase prompt) calling `pairNewDevice` / `unlockDevice` with
  an `createIdbKeyValueStore()` KV + the `api` module as `providerApi`/`bundleApi`;
  call `saveSessions()` after send / on visibility-change.
- Composer precheck + attachment encrypt/decrypt UI.

Hardening before flipping the repos public (crypto audit): the ratchet is
**in-order only** (no skipped-message-key cache); signed-prekey rotation +
multi-device session routing polish. Git push of the 3 repos remains deferred.
