# 2026-05-30 — Daily wrap-up

Two threads today: **finishing the S28 meinchat-plus hardening** and a
**live-debugging session** on the running localhost stack (a prod-class
migration bug + image rendering + large-upload limits), plus the sprint
carry-forward housekeeping.

## 1. S28 meinchat-plus hardening — COMPLETE

Detailed reports live in the S28 sequence: [`../../20260528/reports/20-meinchat-plus-hardening-audit-e2e.md`](../../20260528/reports/20-meinchat-plus-hardening-audit-e2e.md)
and [`../../20260528/reports/21-localhost-meinchat-demo-and-protocol-500-fix.md`](../../20260528/reports/21-localhost-meinchat-demo-and-protocol-500-fix.md).

- **Skipped-message-key cache (Signal MKSKIPPED)** in `crypto/ratchet.ts` —
  out-of-order + cross-DH-ratchet delivery now tolerated, single-use, bounded by
  `MAX_SKIP=1000`. Ratchet is no longer in-order-only.
- **E2E thumbnails re-enabled** (the cache removed the desync that forced
  fullres-only) — `sendEncryptedImage` uploads fullres + thumb; `hydrateRow`
  decrypts both in order.
- **Signed-prekey rotation** — `establishInbound` matches current OR previous
  signed prekeys (stale-bundle peers still cold-start).
- **Multi-device** documented as a v1 limitation (fan-out only).
- **Crypto audit doc** `plugins/meinchat-plus/docs/crypto-audit.md` — primitives,
  construction, threat model, **known limits before public** (headline gap: no
  identity-key verification UX / safety numbers).
- **Playwright API smoke** `plugins/meinchat-plus/tests/e2e/prod-e2e.spec.ts`
  (device→prekeys→bundle fetch + client-side signature verify → `e2e_v1`).
- **Type-safety cleanup** — provider returns canonical meinchat
  `MessageRow`/`MessageAttachment`, reads via a DRY/ISP `InboundRow`.
- **Gates:** fe-user meinchat + meinchat-plus **156 vitest specs** green, eslint
  clean, meinchat-plus **vue-tsc clean**.

Remaining before flipping the 3 repos public: an **independent crypto review** +
**identity-key verification UX**. Git push of the repos stays **deferred**.

## 2. Live-debugging the running localhost stack

Triggered by browser 500s + an image that wouldn't render. Full detail in
[`../../20260528/reports/21-...md`](../../20260528/reports/21-localhost-meinchat-demo-and-protocol-500-fix.md).

- **500 `column conversation.protocol does not exist`** — `meinchat`+`meinchat_plus`
  were enabled but the **DB was never migrated** (stuck at `20260424_1015`).
  `alembic upgrade heads` first tripped on two revision ids exceeding the stock
  `alembic_version VARCHAR(32)` → widened that column to 255, re-ran, all
  meinchat-E2E migrations applied. `GET/POST /conversations` → 200.
- **Images served as `octet-stream`** (wouldn't render) — `/uploads/<path>` is
  served by CMS `serve_upload`, whose `mimetypes` registry doesn't know `.webp` →
  octet-stream. Registered `.webp`/`.avif`/`.svg` + explicit mimetype → now
  `image/webp`. Verified rendering of a real screenshot upload + a test image.
- **Allow large image files** — nginx `client_max_body_size` was unset (1 MB cap)
  → set `40m` in `nginx.dev.conf` + `nginx.prod.conf.template`; meinchat
  `attachment_max_bytes` 5 MB → 25 MB, `attachment_max_dimension_px` 2048 → 4096.
- **Browser demo (Bob ↔ Alice, localhost:8080)** — Playwright
  `plugins/meinchat/tests/e2e/localhost-demo.spec.ts`, **3/3 passed**:
  conversation + text, a **real token transfer**, and image render. Screenshots in
  [`../../20260528/reports/screenshots/`](../../20260528/reports/screenshots/).
  *(Caveat: the live fe-user bundle loads base `meinchat` only — `meinchat-plus`
  E2E isn't bundled, so this demo is over plain meinchat; the E2E layer is covered
  by the 156 unit specs + the API smoke.)*
- **Regression gate:** `plugins/meinchat` config + `plugins/cms` tests **192 passed**.

Backend/nginx/config edits applied to the running stack (api restart + nginx
container recreate). **Not committed** (standing rule); the nginx-prod-template +
meinchat-config changes reach prod only on a redeploy.

## 3. Housekeeping — sprint carry-forward

Created today's folder `docs/dev_log/20260530/` (`sprints/`, `reports/`, `done/`).
Moved the **19 still-PLANNED/DRAFT sprints** out of `20260528/sprints/` into
`20260530/sprints/`: S30 (×2), S31, S32, S33, S34, S35, S36, S37, S40, S41,
S42 (vbwd-press: parent + 0–4), S28.6/S28.7 (iOS). Left in `20260528/`: the S28
epic strategy docs (master + phase1 + phase2 — the now-mostly-delivered epic
record) and **S39** (implemented backend). `_engineering_requirements.md` copied
into today's folder.

## Open follow-ups (small, not done)

- Two meinchat migration revision ids exceed 32 chars (`20260602_1000_meinchat_attachment`,
  `20260603_1000_drop_msg_attach_cols`) — shorten so a stock `alembic_version`
  table doesn't choke on a fresh DB.
- meinchat `config.json` exposes `image_max_size_bytes` to admins, but the service
  reads `attachment_max_bytes` from DEFAULT_CONFIG — reconcile the two keys.
