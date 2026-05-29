# S28.4 — Attachment encryption (mirror of S28.3 on the file-write/read path)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb the
critical review:
- **No separate `IAttachmentCodec` port.** Encryption happens on the
  client (mirrors the corrected S28.3b model); the server-side write
  path just stores opaque bytes. A whole new port for a one-shot
  pass-through was overengineering; folded into the existing
  attachment-write flow with a `protocol` discriminator (DRY).
- **Dual-blob thumbnails get a real schema.** Earlier draft said "two
  ciphertext blobs, one tagged `kind: 'thumb'`" but the migration only
  added per-row columns. New `meinchat_attachment` child table with
  `kind` enum (`fullres` / `thumb`) closes critical-review §C19.
- **Client encrypts, server forwards** (corrects the same server-side
  encryption hole the critical review flagged for S28.3b — the
  attachment codec was inheriting the same mistake).
- `NoDeviceKeysError` lives in `plugins/meinchat/` once and is re-used
  by both the body codec (S28.3b) and the attachment write (DRY).
**Depends on:** [S28.3a](s28-3a-meinchat-extension-ports.md) (ports), [S28.3b](s28-3b-meinchat-plus-signal-ratchet.md) (codec + device directory).
**Blocks:** nothing.

**Repos touched:**
- `vbwd-backend/plugins/meinchat/` — small port-extraction for the attachment write/read path.
- `vbwd-plugin-meinchat-plus` (NEW from S28.3b) — registers the attachment codec.
- `vbwd-fe-user-plugin-meinchat-plus` + `vbwd-ios-plugin-meinchat-plus` — encrypt before upload, decrypt on download.

**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** all touched plugin CIs GREEN; integration assertion "no plaintext bytes on disk" extended to attachment storage.

---

## 1. Goal

Image / file attachments get the same ciphertext-on-the-server
treatment as message bodies. The plaintext bytes never reach
`IFileStorage`; only ciphertext blobs do. Clients encrypt before upload
and decrypt on download. With meinchat-plus disabled, attachments
continue as today (plain bytes in `IFileStorage`).

This slice is small because the heavy lifting (ratchet, device
directory, key-management UI) already shipped in S28.3b. The codec is
reused — only the *transport* (file-stream vs SQL row) changes.

## 2. Extend meinchat's attachment pipeline (small refactor)

### 2.1 NO new port — DRY, fold into existing write path

The earlier draft introduced `IAttachmentCodec` mirroring `IBodyCodec`.
Both ports would have done the same thing (encode→pass-through on
server, decrypt client-side). **Dropped in this revision** — adding a
port for one pass-through impl is overengineering. Instead, the
attachment service learns to accept opaque bytes + a `protocol`
discriminator, and the meinchat-plus client encrypts before upload.

### 2.2 Schema (single Alembic head, additive) — proper dual-blob support

Earlier draft amended `message` with per-row attachment columns. That
can't carry the fullres + thumb pair the §3 client wants to upload.
**Replaced with a child table:**

```sql
-- One row per attached blob. A "plain" message has zero or one row;
-- an e2e_v1 message has TWO (fullres + thumb), each independently
-- client-encrypted with its own ChaChaPoly key.
CREATE TYPE meinchat_attachment_kind AS ENUM ('fullres', 'thumb');

CREATE TABLE meinchat_attachment (
    id              UUID PRIMARY KEY,
    message_id      UUID NOT NULL REFERENCES message(id) ON DELETE CASCADE,
    kind            meinchat_attachment_kind NOT NULL,
    storage_url     TEXT NOT NULL,             -- IFileStorage URL
    protocol        VARCHAR(32) NOT NULL DEFAULT 'plain',
    envelope_header JSONB NULL,                -- per-recipient key envelopes for e2e_v1; NULL for plain
    mime            VARCHAR(64) NOT NULL,
    bytes_count     INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT meinchat_attachment_one_kind_per_message UNIQUE (message_id, kind),
    CONSTRAINT meinchat_attachment_protocol_or_envelope
        CHECK ((protocol = 'plain' AND envelope_header IS NULL)
            OR (protocol != 'plain' AND envelope_header IS NOT NULL))
);

CREATE INDEX meinchat_attachment_message_idx ON meinchat_attachment (message_id);

-- Backfill: existing single-attachment rows (today's `message.attachment_url`)
-- migrate into the child table as `kind='fullres', protocol='plain'`. After
-- the backfill commit, the old `message.attachment_url` column is removed.
INSERT INTO meinchat_attachment (id, message_id, kind, storage_url, protocol, mime, bytes_count)
SELECT gen_random_uuid(), id, 'fullres', attachment_url, 'plain',
       coalesce(attachment_mime, 'application/octet-stream'),
       coalesce(attachment_bytes, 0)
  FROM message WHERE attachment_url IS NOT NULL;

ALTER TABLE message DROP COLUMN attachment_url;
ALTER TABLE message DROP COLUMN attachment_mime;
ALTER TABLE message DROP COLUMN attachment_bytes;
```

Plain attachments now live in `meinchat_attachment` rows (one per
message). E2E attachments are two rows per message (`fullres` + `thumb`),
each independently encrypted client-side. **Wire contract changes:**
`Message.to_dict()` emits `attachments: [{kind, storage_url,
protocol, envelope_header?, mime, bytes_count}]` instead of
`attachment_url`. Versioned at `protocol = 'plain'` for back-compat —
old clients reading the API see the first `fullres` row's URL in a
compatibility shim until they're upgraded.

### 2.3 `AttachmentService.upload`/`download` refactor

`plugins/meinchat/meinchat/services/attachment_service.py`:

```python
def upload(self, sender, conversation, payload: bytes, *, mime: str,
           protocol: str, envelope_header: dict | None, kind: AttachmentKind) -> Attachment:
    # Server is a forwarder — bytes are already client-encrypted when
    # protocol != 'plain'. Validate shape + size, write to IFileStorage.
    if protocol != "plain":
        if envelope_header is None:
            raise InvalidEnvelopeError("envelope_header required for non-plain protocol")
        # Optional: parse envelope_header.per_recipient_key_envelopes
        # and assert each device_id is in the conversation's addressed
        # set (defence-in-depth; client could already do this).
    ref = self._storage.write(payload, mime=mime)
    return Attachment(message_id=..., kind=kind, storage_url=ref.url,
                      protocol=protocol, envelope_header=envelope_header,
                      mime=mime, bytes_count=len(payload))

def download(self, attachment: Attachment) -> bytes:
    # Returns raw bytes — opaque to the server for protocol != 'plain'.
    # The client decrypts.
    return self._storage.read(attachment.storage_url)
```

**The server never holds plaintext attachment bytes** when `protocol !=
'plain'`. The codec is gone; the discriminator + opaque bytes is
enough.

## 3. meinchat-plus contribution — client-side encryption (no server-side codec)

The earlier draft had a `SignalAttachmentCodec` running server-side —
same E2E violation the critical review flagged for the body codec.
**Removed.** Attachment encryption happens in the meinchat-plus client
plugins (web + iOS); the server-side write path just stores opaque
bytes.

### 3.1 Client-side attachment encryption flow (hybrid scheme)

The hybrid is **symmetric-stream + asymmetric-key-envelope** — an image
can be MBs, so we don't want N libsignal-encrypt operations over the
full payload. Per attachment + per kind (`fullres` / `thumb`):

```
client:
  1. Lookup all addressed devices (peer's + own) via /messaging/users/<id>/devices.
  2. Generate a fresh 256-bit ChaChaPoly key K_att.
  3. Encrypt the file bytes once: ciphertext = ChaChaPoly.encrypt(payload, K_att).
  4. For each addressed device, wrap K_att under the recipient device's
     Signal session: K_envelope[device.id] = libsignal.encrypt(K_att, session_for(device)).
  5. POST /messaging/conversations/<id>/messages/attachments with:
        - the ciphertext bytes (multipart upload)
        - `protocol=e2e_v1`
        - `envelope_header = { "per_recipient_key_envelopes": { device.id: K_envelope[device.id] }, "alg": "chacha20poly1305" }`
        - `kind` in `{"fullres", "thumb"}` — clients upload BOTH (server can't resize ciphertext)

server (validator):
  - Verify size ≤ ciphertext_max_bytes (per attachment).
  - Verify envelope_header.per_recipient_key_envelopes covers exactly the
    addressed device set (defence-in-depth — same as the body codec validator).
  - Write to IFileStorage; persist meinchat_attachment row.

client on read:
  1. GET /messaging/conversations/<id>/messages?since=…
  2. For each attachment with protocol=e2e_v1, fetch the storage URL.
  3. envelope = response.envelope_header.per_recipient_key_envelopes[my_device_id]
     K_att = libsignal.decrypt(envelope, my_session)
  4. plaintext = ChaChaPoly.decrypt(storage_bytes, K_att)
```

**No server-side `SignalAttachmentCodec` class.** No server-side keys.
No server-side encryption code path. The `NoDeviceKeysError` raised
when `IDeviceDirectory.lookup_active(peer.id)` returns `[]` lives in
**`plugins/meinchat/`** (re-used by both the body codec and the
attachment upload — single home, DRY).

### 3.2 Why hybrid (symmetric stream + asymmetric key envelope)

- Image / file can be MB; encrypting the full payload N times for N
  recipient devices would scale badly.
- Hybrid: ciphertext blob is `N=1` (one copy in storage); only the
  256-bit symmetric key is wrapped per-recipient. Linear in device
  count, constant in payload size.

### 3.2 Web — `vbwd-fe-user-plugin-meinchat-plus`

- Reuse the existing `useImageAttach` composable + add a pre-upload
  hook that calls the WebCrypto ChaChaPoly + libsignal-JS wrappers
  (same dependencies S28.3b added — no new libraries).
- Decryption on download is streamed where possible (browser
  WebCrypto stream APIs) so we don't materialise large images in
  memory.

### 3.3 iOS — `vbwd-ios-plugin-meinchat-plus`

- Reuse CryptoKit `ChaChaPoly` + the libsignal Swift package already
  pulled in for S28.3b.
- Streamed encrypt/decrypt via `URLSession` upload/download
  delegates — no full-image in-memory copy.

## 4. TDD plan

### 4.1 Backend — meinchat

`tests/unit/services/test_attachment_service_refactor.py` ≥ 6 specs:

| # | Spec |
|---|---|
| 1 | With default identity codec: upload → bytes in storage are byte-equal to input |
| 2 | With default identity codec: download → bytes returned are byte-equal to stored |
| 3 | Registered fake encrypt codec: stored bytes != input bytes |
| 4 | Registered fake encrypt codec: download with the matching decrypt → equals input |
| 5 | Storage write failure propagates (no silent swallow) |
| 6 | `AttachmentRef.protocol` is persisted on the message row |

### 4.2 Backend — meinchat-plus

`tests/unit/services/test_signal_attachment_codec.py` ≥ 6 specs:

| # | Spec |
|---|---|
| 1 | Round-trip: encode → decode with matched device key recovers bytes |
| 2 | Tamper ciphertext → decode raises |
| 3 | Tamper header (key envelope) → decode raises |
| 4 | Multi-recipient: one ciphertext blob, N key envelopes, each device gets its own key |
| 5 | No device key → encode raises `NoDeviceKeysError` |
| 6 | Different attachments → different per-attachment symmetric keys (verified by inequality of derived keys + nonces) |

`tests/integration/test_e2e_attachment_round_trip.py` ≥ 2 specs:

1. Two users with one device each: send an image → assert `IFileStorage`
   reads back ciphertext bytes (not the input PNG header).
2. Recipient's download via the route returns the plaintext bytes
   byte-for-byte equal to the upload.

### 4.3 Web + iOS

- `plugins/meinchat-plus/tests/unit/crypto/attachment-round-trip.spec.ts` ≥ 3 specs.
- `Tests/MeinChatPlusPluginTests/AttachmentRoundTripTests.swift` ≥ 3 specs.

Both clients also extend the existing useImageAttach / image-picker
specs to assert plain mode is unchanged when meinchat-plus is absent.

## 5. Acceptance criteria

- Default behaviour byte-for-byte unchanged: every existing
  attachment integration test still green without meinchat-plus loaded.
- With meinchat-plus enabled: a PNG sent between two users round-trips
  pixel-equal on the receiver, while `IFileStorage` holds ciphertext.
- `attachment_protocol` discriminator visible on `Message.to_dict()`
  for plus-mode rows; absent for plain rows (or `'plain'` if explicit).
- meinchat's existing thumbnail/resize pipeline (Pillow) **is bypassed
  when `attachment_protocol != 'plain'`** — there's no way to resize
  ciphertext, and the client is responsible for both fullres + thumb
  encryption (we send two ciphertext blobs, one tagged
  `kind: 'thumb'`).
- Integration assertion: `tcpdump`-on-loopback during a manual smoke
  shows ciphertext payload on the upload PUT.

## 6. What this slice explicitly does NOT do

- **Server-side resize / thumbnail.** Mutually exclusive with E2E for
  attachments; the client uploads both fullres + thumb.
- **Stream encryption protocol fanciness.** ChaChaPoly authenticated
  encryption + the existing libsignal session for the key envelope
  is enough. No AES-GCM-SIV, no AGE, no envelope-of-envelope.
- **Content-disposition / MIME sniffing changes.** Out of scope.
- **CDN signed URLs for ciphertext.** Out of scope; same storage
  surface as today.

## 7. Engineering-requirements check

- **TDD-first:** ≥ 15 new specs land before the service-refactor body is written.
- **NO OVERENGINEERING — concrete corrections in this revision.**
  - **No `IAttachmentCodec` port.** Earlier draft introduced a port
    mirroring `IBodyCodec` — but both would do the same thing
    (encode = pass-through; decode = pass-through; clients encrypt).
    A port with one pass-through impl is pure overhead. Folded into
    the existing attachment-write flow.
  - **No server-side `SignalAttachmentCodec`.** Same correction as
    S28.3b's body codec — encryption happens on the client. Removes a
    whole server-side ChaChaPoly + libsignal dependency that wasn't
    earning its keep.
  - **No streaming server-side encryption.** Server never touches
    plaintext bytes; streaming optimisation lives on the client
    (browser WebCrypto stream APIs / iOS URLSession delegates).
- **DRY — concrete corrections.**
  - **One `NoDeviceKeysError`** in `plugins/meinchat/` is raised by
    BOTH the body codec (S28.3b) AND the attachment write path. Single
    contract for "this conversation has no addressed devices".
  - **One `protocol` discriminator** on the new `meinchat_attachment`
    table — matches the shape of `message.protocol`. No second
    discriminator vocabulary.
  - **One `meinchat_attachment` child table** carries both `fullres`
    and `thumb` kinds via an enum, instead of duplicating per-message
    columns. Cleanly handles plain (1 row) and e2e_v1 (2 rows).
- **SOLID — L:** wire contract on the read side is uniform across
  plain + e2e_v1 — every message carries `attachments: [{kind, ...}]`;
  the only difference is whether `envelope_header` is populated.
- **Core agnostic:** meinchat changes are confined to the plugin's own
  files. Everything else lives in meinchat-plus client plugins.
