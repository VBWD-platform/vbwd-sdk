# Report 12 — S28.4 increments 3+4: retention, schema unification, fe migration

**Date:** 2026-05-29
**Sprint:** [S28.4 — attachment encryption](../sprints/s28-4-attachment-encryption.md)
**Follow-up to:** reports [10](10-s28-4-attachment-encryption-storage.md) + [11](11-s28-4-attachment-routes-and-to-dict.md).
**Decision:** product owner confirmed **pre-rollout, no attachment data to
preserve** → the destructive migration needs **no backfill**.
**Gates:** backend meinchat `--full` GREEN · meinchat_plus `--full` GREEN ·
fe-user meinchat 68 specs GREEN + eslint clean · fe-admin meinchat-admin 4
specs GREEN + eslint clean.
**Commits:** none.

## Increment 3 — retention prune deletes child blobs

`RetentionService.prune_attachments` now deletes every
`meinchat_attachment` storage blob for a pruned message (via
`Message.attachments`). +1 unit spec.

## Increment 4 — fold ALL attachments into the child table, drop legacy columns

Backend (`meinchat`):
- `meinchat_attachment` gains nullable `width_px` / `height_px` (server-set
  for plain `fullres`; the fe image layout reads them).
- `MessageService.send_attachment` (plain images) now writes a `fullres`
  child row (with dimensions) + a `thumb` child row instead of the per-row
  `message.attachment_*` columns.
- `Message` model: the 4 `attachment_*` columns + their `to_dict` keys are
  **removed**; `to_dict` emits only `attachments: [...]`.
- `delete_message` purges each child blob from storage; retention reads child
  rows only (legacy URL cleanup removed).
- Migration `20260603_1000_drop_msg_attach_cols` drops the 4 columns
  (**no backfill** — pre-rollout; downgrade re-adds them nullable, data not
  restored). `width_px`/`height_px` added to the create-table migration.
- Backend tests updated to the child-row model (retention, message-service
  delete, integration retention prune).

Frontend (wire-contract migration — `attachment_url` → `attachments[]`):
- **fe-user `meinchat`**: `MessageRow.attachments: MessageAttachment[]`;
  `MessageBubble.vue` renders the **plain** `fullres` blob's `storage_url`
  and skips `e2e_v1` (opaque ciphertext — rendered later by the plus client);
  store optimistic row + all specs updated; +2 image-render specs.
- **fe-admin `meinchat-admin`**: inspector renders plain attachments, shows a
  "🔒 encrypted attachment" badge for `e2e_v1` (moderation must not decrypt).

**iOS NOT touched** — `vbwd-ios-plugin-meinchat` is owned by the iOS agent.
Because the backend dropped `attachment_url` from the wire, **the iOS client
must migrate to `attachments[]`** (coordinate with the iOS agent). Flagged in
the handoff.

## Increment 5 — fe-user + iOS client crypto — SCOPED, deferred to a dedicated session

Greenfield + security-critical, so deliberately NOT rushed here:
- No `vbwd-fe-user-plugin-meinchat-plus` exists yet; no `@signalapp/libsignal-client`
  / `hash-wasm` / `cbor-x` deps in fe-user.
- Scope (spec §3): new fe-user plugin — Argon2id-derived KEK over an IndexedDB
  identity/session store; X3DH + double-ratchet via libsignal-JS; per-recipient
  fan-out (peer + own devices); 256B-padded plaintext; CBOR envelope matching
  `SignalEnvelopeValidator`; attachment hybrid (ChaChaPoly stream + per-recipient
  libsignal key envelope, both `fullres`+`thumb`); downgrade fail-closed;
  composer precheck. Test plan: spec §3.8 (≥14 specs) + §4.2 attachment specs.
- iOS counterpart (S28.7) is the iOS agent's; backend contract is frozen +
  proven by the server-side round-trip tests.

**Recommendation:** run increment 5 as its own focused session with the
public-repo + (optional) external-audit posture the spec calls for.
