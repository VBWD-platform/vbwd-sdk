# Report 21 — localhost meinchat demo (Bob ↔ Alice) + `conversation.protocol` 500 fix

**Date:** 2026-05-30
**Instance:** running localhost stack (`vbwd-backend` :5000, `vbwd-fe-user` nginx :8080) from the workspace.

## 1. Live bug found & fixed — `/api/v1/messaging/conversations` 500

Opening `/dashboard/messages` threw **500** on `GET`/`POST .../conversations`:

```
psycopg2.errors.UndefinedColumn: column conversation.protocol does not exist
```

**Root cause:** the running backend had `meinchat` **and** `meinchat_plus` enabled
in `plugins.json` (so the code reads/writes `conversation.protocol` for protocol
negotiation), but the **DB was never migrated** — alembic was at `20260424_1015`,
missing the whole meinchat-E2E migration chain.

**Fix (alembic only, no raw DDL to app tables):**
1. `alembic upgrade heads` first failed at
   `StringDataRightTruncation` — revision id `20260602_1000_meinchat_attachment`
   (33 chars) overflows the default `alembic_version.version_num VARCHAR(32)`.
   Widened that bookkeeping column: `ALTER COLUMN version_num TYPE VARCHAR(255)`.
   *(Note for the migration authors: two revision ids exceed 32 chars —
   `20260602_1000_meinchat_attachment`, `20260603_1000_drop_msg_attach_cols` —
   which trips a fresh DB on the stock alembic table. Worth shortening.)*
2. Re-ran `alembic upgrade heads` — applied `20260528_1100_meinchat_e2e`
   (adds `conversation.protocol` + capabilities/e2e columns) →
   `20260601_1000_meinchat_plus` (device keys, prekeys, delivery) →
   `20260602_1000_meinchat_attachment` → `20260603_1000_drop_msg_attach_cols`.

**Verified:** `conversation.protocol` present; `GET /conversations` → 200;
`POST /conversations` → 200 (returns `"protocol":"plain"`).

## 2. Playwright demo — Bob ↔ Alice on localhost:8080

Spec: `vbwd-fe-user/plugins/meinchat/tests/e2e/localhost-demo.spec.ts`
(env-gated on `E2E_BASE_URL`; drives Chromium against the running nginx).

```
E2E_BASE_URL=http://localhost:8080 npx playwright test \
  plugins/meinchat/tests/e2e/localhost-demo.spec.ts --project=chromium --workers=1
```

Result: **3 passed (4.0s).**

| # | Flow | Screenshot |
|---|------|-----------|
| 1 | Conversation — open + send a text message through the composer | `screenshots/01-conversation.png` |
| 2a | Token sending — Send Tokens dialog (amount 5 + note) | `screenshots/02a-token-dialog.png` |
| 2b | Token sending — **real transfer**, system bubble `💰 @bob sent 5 tokens to @alice` | `screenshots/02b-token-sent.png` |
| 3 | Image sending — attach → upload → rendered `<img>` bubble | `screenshots/03-image-sent.png` |

**Driver:** Bob = `test@example.com` (nickname `bob`, balance 2000) — chosen so the
token transfer actually settles (Alice = `admin@example.com`, nickname `alice`,
balance 0). All three actions performed through the real UI, not the API.

## 3. Important scope note — this is PLAIN meinchat, not the E2E layer

The live fe-user nginx bundle on :8080 loads **base `meinchat` only**. The
`meinchat-plus` E2E plugin was built this session and is **not in that bundle's
plugin glob** (it would need a fe-user rebuild + per-user device pairing). So the
client never offers `e2e_v1` and every conversation negotiates `"plain"` — the
screenshots show working chat/tokens/images over plain meinchat.

The **E2E (meinchat-plus) layer** is instead proven by:
- **156 vitest specs** (crypto round-trips, skipped-key cache, pairing, attachment
  hybrid-encrypt, store wiring) — green, tsc-clean.
- The **API-level prod smoke** `plugins/meinchat-plus/tests/e2e/prod-e2e.spec.ts`
  (device → signed prekey → OTKs → bundle fetch + **client-side signature verify**
  → conversation negotiates `e2e_v1`).

To demo true E2E in the browser, the next step is: rebuild the fe-user bundle with
`meinchat-plus` enabled, then pair both Bob and Alice (passphrase → Argon2id KEK).
That's a separate, heavier task — flagged, not done here.

## 4. Second live bug — images served as `octet-stream` (wouldn't render)

The console/Network showed the image attachment loading `200` but **Type
`octet-stream`** → the `<img>` couldn't render (looked like an empty bubble).

**Root cause:** `/uploads/<path>` is served by the CMS plugin's `serve_upload`
(`plugins/cms/src/routes.py`) via `send_from_directory`, which derives the
Content-Type from `mimetypes.guess_type`. This base image's `mimetypes` registry
**doesn't know `.webp`** (`guess_type('x.webp') → (None, None)`) → falls back to
`application/octet-stream`. (png/jpg were fine; webp is what meinchat encodes to.)

**Fix:** register the modern image types at import (`mimetypes.add_type` for
`.webp`/`.avif`/`.svg`) and pass an explicit `mimetype` to `send_from_directory`.
Now `/uploads/...webp` serves **`Content-Type: image/webp`** — verified via
nginx :8080 (`200, image/webp, RIFF…WEBP`), and both a real screenshot upload and
a test image render in the chat (`screenshots/03-image-sent.png`).

## 5. "Allow large image files"

Two caps were blocking big uploads:
- **nginx `client_max_body_size` was unset → 1 MB default** (the hard gate; a >1 MB
  photo 413s before reaching Flask). Set `client_max_body_size 40m;` in both
  `vbwd-fe-user/nginx.dev.conf` and `nginx.prod.conf.template` (40 MB covers a
  25 MB image + ~33% base64 inflation on the e2e JSON path).
- **meinchat `attachment_max_bytes` 5 MB → 25 MB**, `attachment_max_dimension_px`
  2048 → 4096 (`plugins/meinchat/__init__.py` DEFAULT_CONFIG). Images are still
  downscaled + re-encoded to webp, so stored size stays small; this just stops big
  source photos from being rejected.

**Applied to the running stack:** restarted `api` (mimetype + config) and the
nginx container (the bind-mounted conf — a macOS mount-sync lag served a truncated
file until the container was recreated). Gate: `plugins/meinchat` config +
`plugins/cms` tests **192 passed**. (Note: the admin-facing `image_max_size_bytes`
key in meinchat `config.json` is NOT the key the service reads — it uses
`attachment_max_bytes` from DEFAULT_CONFIG; reconciling those two is a small
follow-up, not done here.)
