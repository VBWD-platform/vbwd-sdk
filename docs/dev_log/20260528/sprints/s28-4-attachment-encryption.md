# S28.4 — Attachment encryption (mirror of S28.3 on the file-write/read path)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
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

### 2.1 New port — `IAttachmentCodec`

`plugins/meinchat/meinchat/extensibility/attachments.py`:

```python
class IAttachmentCodec(Protocol):
    """Encode an attachment payload on the way to storage; decode on the
    way back. Mirrors IBodyCodec but for byte streams.

    Single-impl; last-write-wins. Default in meinchat = identity
    (passthrough) — bytes go to IFileStorage unmodified."""

    def encode(self, ctx: AttachmentSendContext, payload: bytes) -> EncodedAttachment: ...
    def decode(self, ref: AttachmentRef, viewer_device: Device | None) -> bytes: ...
```

`EncodedAttachment` carries `{ciphertext: bytes, protocol: str, header: dict}`.
`AttachmentRef` is the persisted reference (storage URL + protocol +
header). The header lives in a small new sibling JSONB column
`message.attachment_envelope_header` (migration in S28.4 only — no
re-touching of the S28.3a schema additions).

### 2.2 Schema (single Alembic head, additive)

```sql
ALTER TABLE message
    ADD COLUMN attachment_protocol VARCHAR(32) NOT NULL DEFAULT 'plain',
    ADD COLUMN attachment_envelope_header JSONB NULL;
```

Plain attachments (today's flow) leave both at the default — `'plain'`
and `NULL`. Encrypted attachments set both.

### 2.3 `AttachmentService.upload`/`download` refactor

`plugins/meinchat/meinchat/services/attachment_service.py`:

```python
def upload(self, sender, conversation, payload: bytes, *, mime: str) -> AttachmentRef:
    codec = resolve_first(IAttachmentCodec)
    encoded = codec.encode(AttachmentSendContext(...), payload)
    ref = self._storage.write(encoded.ciphertext, mime=mime)        # IFileStorage unchanged
    return AttachmentRef(url=ref.url, protocol=encoded.protocol, header=encoded.header)

def download(self, attachment_ref: AttachmentRef, viewer_device: Device | None) -> bytes:
    codec = resolve_first(IAttachmentCodec)
    ciphertext = self._storage.read(attachment_ref.url)
    return codec.decode(attachment_ref, viewer_device)
```

Default `IdentityAttachmentCodec` registered in meinchat's `on_enable` —
same shape as `IdentityBodyCodec` from S28.3a (encode is passthrough,
decode is passthrough). Behavior unchanged for any deploy without
meinchat-plus.

## 3. meinchat-plus contribution

### 3.1 `SignalAttachmentCodec`

`meinchat-plus/meinchat_plus/services/signal_attachment_codec.py`:

```python
class SignalAttachmentCodec(IAttachmentCodec):
    def encode(self, ctx, payload: bytes) -> EncodedAttachment:
        recipients = resolve_first(IDeviceDirectory).lookup_active(ctx.recipient_id)
        if not recipients:
            raise NoDeviceKeysError(...)                  # strict fallback
        # ChaChaPoly stream encrypt with a fresh key per attachment,
        # then seal the key once per recipient device via the existing
        # ratchet session. Lets us store a single ciphertext blob in
        # IFileStorage + a small per-recipient key envelope in the header.
        key = ChaChaPoly.fresh_key()
        ciphertext = ChaChaPoly.encrypt(payload, key)
        per_recipient = {device.id: libsignal.encrypt(key, device.public_key)
                         for device in recipients}
        return EncodedAttachment(
            ciphertext=ciphertext,
            protocol="e2e_v1",
            header={"per_recipient_key_envelopes": per_recipient, "alg": "chacha20poly1305"},
        )

    def decode(self, ref, viewer_device):
        envelope = ref.header["per_recipient_key_envelopes"][str(viewer_device.id)]
        key = libsignal.decrypt(envelope, viewer_device.private_key)
        return ChaChaPoly.decrypt(self._storage.read(ref.url), key)
```

Registered in meinchat-plus's `on_enable` alongside the body codec.
**Why the hybrid (symmetric-stream + asymmetric-key-envelope) instead
of envelope-per-recipient like message bodies:** an image can be MB
of data and we'd otherwise have to encrypt the full payload N times
for N recipient devices. The hybrid lets the ciphertext blob be N=1
and only the small key is per-recipient.

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

- **TDD-first:** ≥ 15 new specs land before the codec or service-refactor body is written.
- **DRY:** the same registry resolver pattern from S28.3a powers
  `IAttachmentCodec`. Same `NoDeviceKeysError` is raised by the
  attachment codec and the body codec — single home for that contract.
- **SOLID — S/O:** the attachment codec is a separate port (one job),
  so a future "compress before encrypt" codec could replace it
  without touching meinchat-plus.
- **SOLID — L:** identity codec round-trips byte-for-byte; Signal codec
  round-trips bytes when the keys are right. Substitutable contract.
- **NO OVERENGINEERING:** one extra port, one schema discriminator,
  one impl per plugin. No new abstractions.
- **Core agnostic:** meinchat changes are confined to the plugin's own
  files. Everything else lives in meinchat-plus.
