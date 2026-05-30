# Report 11 — S28.4 attachment encryption: e2e routes + to_dict attachments[] (increment 2)

**Date:** 2026-05-29
**Sprint:** [S28.4 — attachment encryption](../sprints/s28-4-attachment-encryption.md)
**Follow-up to:** [report 10](10-s28-4-attachment-encryption-storage.md) (storage layer).
**Gates:** `--plugin meinchat --full` GREEN · `--plugin meinchat_plus --full` GREEN.
**Commits:** none (plugins gitignored).

## What landed (still additive — plain path untouched)

A cleaner, RESTful split rather than the spec's bundled multipart upload:
message creation stays on `POST /messages` (`envelope_b64`); attachments
upload + download are their own single-purpose endpoints (SOLID-S), and the
service layer is unit-testable without the codec/registry.

**meinchat:**
- **`Message.to_dict()` now emits `attachments: [{id, kind, storage_url,
  protocol, envelope_header?, mime, bytes_count}]`** — ADDITIVE: the legacy
  `attachment_url`/`attachment_thumb_url`/… fields stay for back-compat until
  every client reads `attachments[]`. Backed by a `Message.attachments`
  relationship (`lazy="selectin"`, cascade delete-orphan, string class ref to
  avoid an import cycle).
- **`MessageService.add_e2e_attachment(message_id, *, caller_user_id, kind,
  ciphertext, envelope_header, mime)`** — only the message's sender may
  attach; rejects plain messages (`PlainAttachmentError`); stores opaque
  ciphertext via `AttachmentService.store_encrypted`; records the
  `meinchat_attachment` child row with the per-recipient key envelope.
- **`MessageService.get_attachment_blob(attachment_id, *, caller_user_id)`** —
  returns `(bytes, mime)` only if the caller is a participant of the
  attachment's conversation; opaque ciphertext for e2e (the client decrypts).
  `AttachmentNotFoundError` is returned for both missing AND not-authorised
  (no probing).
- **Routes:** `POST /api/v1/messaging/messages/<msg_id>/attachments` (JSON:
  `kind`, `ciphertext_b64`, `envelope_header`, `mime`; rate-limited
  `attachment_send`); `GET /api/v1/messaging/attachments/<attachment_id>`
  (raw opaque bytes, `application/octet-stream`).
- `AttachmentRepository.find_by_id`; `MessageService` gains an injected
  `attachment_repo`; the route factory wires it.

## Tests (TDD, all green)

- `tests/unit/services/test_e2e_attachment_service.py` (7) — store-opaque +
  row recorded; unknown/foreign/plain message rejected; blob read for a member;
  missing + non-member → `AttachmentNotFoundError`.
- meinchat-plus `tests/integration/test_e2e_attachment_round_trip.py` (2) —
  full HTTP round-trip: send e2e message → upload encrypted fullres blob →
  it appears under the message's `attachments[]` → peer downloads byte-equal
  ciphertext; the persisted row is `protocol=e2e_v1` with a non-null
  `envelope_header`. Plus: a non-participant is denied (404).
- meinchat `--full` GREEN (existing attachment/resize/retention specs
  unchanged); meinchat-plus `--full` GREEN.

## Deliberate deviations from the spec (noted)

- **JSON + base64 upload, not multipart.** Consistent with the message
  `envelope_b64` contract the rest of meinchat-plus uses, and trivially
  testable. Multipart streaming is a client perf optimisation, deferred.
- **Attachment decoupled from message creation** (two endpoints) instead of
  one bundled `…/messages/attachments` create-call — RESTful, each route one
  job, service unit-testable without the codec.

## Remaining S28.4 increments

3. **Retention prune** must also delete `meinchat_attachment` blobs
   (extend `RetentionService.prune_attachments` to read child rows).
4. **DESTRUCTIVE** (reconcile the spec drift first — see report 10): fold
   plain attachments into the child table + backfill + drop the legacy
   `message.attachment_*` columns; migrate fe-user/fe-admin/iOS to read
   `attachments[]` before the drop.
5. **Client crypto** (fe-user + iOS): hybrid ChaChaPoly stream + per-recipient
   libsignal key envelope; upload both `fullres` + `thumb` blobs.
