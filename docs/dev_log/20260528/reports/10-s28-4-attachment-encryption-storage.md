# Report 10 — S28.4 attachment encryption: server storage layer (increment 1)

**Date:** 2026-05-29
**Sprint:** [S28.4 — attachment encryption](../sprints/s28-4-attachment-encryption.md)
**Gate:** `bin/pre-commit-check.sh --plugin meinchat --full` → **GREEN**.
**Commits:** none (plugins gitignored).

## Scope of this increment (deliberately bounded + additive)

The spec frames S28.4 as "small", but in practice it's a **core message-schema
+ wire-contract change** touching 46 backend references plus the fe-user,
fe-admin and iOS attachment readers — and the spec's migration backfills from
`attachment_mime`/`attachment_bytes` columns **that don't exist** (the real
`message` schema has `attachment_url`/`attachment_thumb_url`/`attachment_width_px`/
`attachment_height_px`). So this was sequenced as safe, additive increments.

**Increment 1 (this report) — the server-side ciphertext storage layer, fully
additive, breaks nothing:**

- **`meinchat_attachment` child table** (`models/attachment.py`): one row per
  blob — `kind` (`fullres`/`thumb`, CHECK-constrained), `storage_url`,
  `protocol` discriminator, `envelope_header` (JSON, `none_as_null=True` so a
  Python `None` is SQL NULL — the protocol/envelope CHECK depends on it),
  `mime`, `bytes_count`. `UNIQUE(message_id, kind)` + the protocol/envelope
  CHECK.
- **Migration** `20260602_1000_meinchat_attachment` — **CREATE TABLE only**.
  Chains off the meinchat e2e head (`20260528_1100_meinchat_e2e`), NOT the
  meinchat-plus migration, so meinchat's chain still resolves standalone.
  Applied via `alembic upgrade heads` (the repo already runs multi-head).
  **No backfill, no column drop** in this increment — plaintext attachments
  stay on their existing `message.attachment_*` columns and the server-resize
  path is untouched, so plain behaviour is byte-for-byte unchanged.
- **`AttachmentRepository`** — `add` / `list_by_message` /
  `storage_urls_for_message`.
- **`AttachmentService.store_encrypted(ciphertext, *, owner_user_id, kind,
  mime, protocol)`** + **`read_blob(storage_path)`** — the server is a pure
  forwarder: it validates size + kind, writes the **opaque** client ciphertext
  to `IFileStorage`, and returns its coordinates. It never decodes, resizes,
  or strips EXIF for non-plain blobs. **No server-side `SignalAttachmentCodec`,
  no server-side keys** (matches the corrected S28.3b model).

## Tests (TDD, all green)

- `tests/unit/services/test_attachment_encryption.py` (6) — opaque bytes stored
  byte-equal; thumb kind; rejects `plain` protocol / unknown kind / oversize;
  `read_blob` returns the stored ciphertext.
- `tests/integration/test_attachment_repository.py` (4) — add+list+urls;
  one-kind-per-message UNIQUE; protocol/envelope CHECK (e2e without header →
  IntegrityError); plain-with-header → IntegrityError.
- meinchat `--full` GREEN; existing attachment/resize/retention specs
  unchanged; meinchat_plus unit 49 still green.

## Remaining S28.4 increments (next session)

These are the wire-contract + destructive parts, to be done carefully with
full cross-surface regression:

1. **e2e attachment upload/download routes** (`POST …/messages/attachments`
   accepting ciphertext + `envelope_header` + `kind`; download returns opaque
   bytes). Defence-in-depth: assert `envelope_header.per_recipient_key_envelopes`
   covers exactly the addressed device set (reuse the body-codec pattern).
2. **`Message.to_dict()` → `attachments: [{kind, storage_url, protocol,
   envelope_header?, mime, bytes_count}]`** — additive first (keep
   `attachment_url` shim), then migrate the **fe-user / fe-admin / iOS**
   readers, then flip.
3. **Retention cleanup** to delete child-row blobs (extend
   `RetentionService.prune_attachments` to read `meinchat_attachment`).
4. **Destructive**: fold plain attachments into the child table + backfill +
   `DROP COLUMN message.attachment_url/thumb_url/width_px/height_px` — last,
   once all readers consume `attachments[]`.
5. **Client crypto** (fe-user + iOS): hybrid ChaChaPoly stream + per-recipient
   libsignal key envelope; upload both `fullres` + `thumb` ciphertext blobs.

## Engineering notes

- Used a CHECK-constrained `VARCHAR` for `kind` rather than a PG `ENUM` (no
  `CREATE TYPE` so model `create_all` and the migration agree without drift) —
  same rationale as the meinchat-plus partial-index decision.
- Black on `plugins/meinchat/` IS enforced (not gitignore-skipped like the
  brand-new `meinchat_plus/` dir) — formatted the 4 new files; flake8 clean.
