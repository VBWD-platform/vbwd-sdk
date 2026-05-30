# S28 handoff — E2E encryption + retention (resume here)

**Updated:** 2026-05-29 (end of day). **Start tomorrow from this file.**
Strategy/threat-model/locked-decisions: [`sprints/s28-meinchat-e2e-encryption-and-retention.md`](sprints/s28-meinchat-e2e-encryption-and-retention.md).
Phase-2 master: [`sprints/s28-phase2-e2e-and-ios.md`](sprints/s28-phase2-e2e-and-ios.md).
Engineering reqs (BINDING): [`sprints/_engineering_requirements.md`](sprints/_engineering_requirements.md).

**Standing rules:** TDD-first; gate = `bin/pre-commit-check.sh --plugin <name> --full`
green; **no commits without explicit ask**; never edit prod/install trees;
no `# noqa`/`# type: ignore` without asking.

---

## 1. Status board

| Sub-sprint | State | Where |
|---|---|---|
| S28.0 config + `/limits` | ✅ DONE & green | `done/s28-0-...md` |
| S28.1 server retention prune | ✅ DONE & green | `done/s28-1-...md` |
| S28.2 client local cache | ✅ DONE & green | `done/s28-2-...md` |
| **S28.3a** extension ports | ✅ DONE & green (241 specs) | `done/s28-3a-...md` |
| **S28.3b** meinchat-plus | 🟢 BACKEND DONE + ENABLED + full e2e round-trip green; web/iOS client crypto pending | `done/s28-3b-...md`, `reports/08-...md`, `reports/09-...md` |
| S28.4 attachment encryption | ⛔ not started | `sprints/s28-4-...md` |
| S28.6 iOS meinchat update | 🟡 in progress (iOS agent) | `sprints/s28-6-...md` |
| S28.7 iOS meinchat-plus | 🟡 in progress (iOS agent) | `sprints/s28-7-...md` |

**Backend lives in this SDK workspace** under `vbwd-backend/plugins/`. The
fe-user + iOS meinchat-plus crypto clients are the separate piece (iOS agent +
a focused web pass); **do not certify the web double-ratchet without its crypto
specs passing.**

## 2. What's already built (don't redo)

### S28.3a (meinchat) — complete
- `plugins/meinchat/meinchat/extensibility/` — `registry.py` (resolve_first/all,
  register/unregister/reset_for_tests, type-checked), `pipeline.py`
  (`IBodyCodec`, `IPostSendHook`, `SendContext`, `EncodedBody`,
  `IdentityBodyCodec`), `lifecycle.py` (`IConversationPolicy`,
  `IConversationCapabilities`, `BlockListPolicy`, `PlainCapability`),
  `identity.py` (`IDeviceDirectory`, `Device`, `NullDeviceDirectory`,
  `DirectoryNotEnabledError`), `errors.py` (`NoDeviceKeysError`).
- `models/message.py` — `envelope`/`protocol`/`delivered_to_all_addressed_devices_at`,
  `body` nullable, `ck_message_body_len` + `ck_message_body_or_envelope` checks,
  `to_dict` emits `protocol` + base64 `envelope`.
- `models/conversation.py` — `protocol` + `capabilities` (JSONB).
- `services/message_service.py` — `send_text` routes through
  `IBodyCodec`/`IPostSendHook` (identity-codec fallback when registry empty).
- `routes.py` — `GET /messaging/capabilities[?me=true]`, `start_conversation`
  negotiation (`_negotiate_protocol` + `_NegotiationError`, 409/400 contract),
  helpers `_server_capabilities()` / `_device_directory()`.
- `__init__.py` `on_enable` registers the 4 single/multi defaults.
- Migration `migrations/versions/20260528_1100_meinchat_e2e_columns.py`
  (down_revision `20260424_1015`) — incl. protocol-immutable PG trigger.
- Tests: `tests/unit/extensibility/` (23), `tests/unit/routes/test_capabilities_endpoint.py`,
  `tests/unit/routes/test_negotiate_protocol.py`, `tests/unit/test_no_downstream_imports.py`.

### S28.3b (meinchat_plus) — started
- `plugins/meinchat_plus/` — `__init__.py` (`MeinChatPlusPlugin`,
  name=`meinchat_plus`, `dependencies=["meinchat"]`, `DEFAULT_CONFIG`,
  `on_enable` registers the validator only — extend as services land),
  `config.json`, `admin-config.json`.
- `meinchat_plus/services/signal_envelope_validator.py` — `SignalEnvelopeValidator`
  (+ `InvalidEnvelopeError`/`EnvelopeTooLargeError`/`UnknownRecipientDeviceError`/
  `MalformedEnvelopeError`). Server validates CBOR grammar + size + unknown-device;
  **holds no keys, never decodes.**
- `tests/unit/services/test_signal_envelope_validator.py` — 9 specs green.
- `cbor2==5.6.2` added to `requirements.txt`.

## 3. Next increment — S28.4 attachment encryption (was: S28.3b backend + meinchat-wiring ✅ DONE 2026-05-29)

**S28.3b is now BACKEND-COMPLETE, ENABLED, and the full e2e round-trip is
green** (server side). Reports: [`08`](reports/08-s28-3b-backend-persistence.md)
(persistence) + [`09`](reports/09-s28-3b-meinchat-wiring-and-enable.md)
(meinchat-wiring + enable). meinchat send/read/prune now route through the
S28.3a ports; `meinchat_plus` is enabled in `plugins.json`/`config.json`;
`bin/pre-commit-check.sh --plugin meinchat --full` AND `--plugin meinchat_plus
--full` both GREEN. **Remaining for S28.3b: the fe-user + iOS client crypto**
(real libsignal — separate repos; iOS in progress by the iOS agent).

**S28.4 — attachment encryption: increment 1 DONE & green 2026-05-29**
([`reports/10-...md`](reports/10-s28-4-attachment-encryption-storage.md)).
Server ciphertext storage layer landed (additive, breaks nothing):
`meinchat_attachment` child table + migration `20260602_1000_meinchat_attachment`
(CREATE TABLE only — chains off the meinchat e2e head, standalone-resolvable),
`AttachmentRepository`, `AttachmentService.store_encrypted`/`read_blob`
(server stores opaque client ciphertext, never decodes/resizes). 6 unit + 4
integration green; meinchat `--full` GREEN.

**SPEC DRIFT to fix in the next increment:** the spec's migration backfills
from `attachment_mime`/`attachment_bytes` columns that DON'T EXIST — the real
`message` schema has `attachment_url`/`attachment_thumb_url`/`attachment_width_px`/
`attachment_height_px`. Reconcile before the destructive column-drop.

**S28.4 increment 2 DONE & green 2026-05-29**
([`reports/11-...md`](reports/11-s28-4-attachment-routes-and-to-dict.md)): e2e
attachment routes (`POST /messages/<id>/attachments`, `GET /attachments/<id>`),
`Message.to_dict() attachments[]` (additive), `add_e2e_attachment` /
`get_attachment_blob`; full HTTP round-trip green (upload opaque ciphertext →
appears under `attachments[]` → peer downloads byte-equal; non-participant 404).
Both gates GREEN.

**S28.4 increments 3+4 DONE & green 2026-05-29**
([`reports/12-...md`](reports/12-s28-4-schema-unification-and-fe-migration.md)):
retention prunes child blobs; ALL attachments folded into `meinchat_attachment`
(plain `send_attachment` → fullres+thumb child rows; +nullable width/height);
legacy `message.attachment_*` columns DROPPED (`20260603_1000`, **no backfill —
pre-rollout per product owner**); `to_dict` emits only `attachments[]`; fe-user
`meinchat` + fe-admin `meinchat-admin` migrated to `attachments[]`. All gates
GREEN (backend meinchat/meinchat_plus `--full`; fe-user 68; fe-admin 4).

**⚠️ iOS coordination:** the backend wire dropped `attachment_url` →
`vbwd-ios-plugin-meinchat` (iOS agent) MUST migrate to `attachments[]` or
attachment rendering breaks. Server contract is frozen.

**S28.4 attachment client crypto DONE & green 2026-05-30** —
`meinchat-plus/src/crypto/attachment.ts` hybrid (one ChaCha20-Poly1305 blob +
per-recipient ratchet-wrapped key envelope): `encryptAttachment`/`decryptAttachment`;
2-device fan-out + tamper specs (fe-user 118). Completes S28.4 §3 crypto →
**`s28-4-...md` moved `sprints/ → done/`**. UI glue (image picker → encrypt →
upload; download → decrypt → render) remains, same as the text composer.

**S28.4 increment 5 — fe-user client crypto BUILT & green 2026-05-29**
([`reports/13-...md`](reports/13-meinchat-plus-repos-and-fe-user-crypto.md)).
3 PRIVATE repos created under VBWD-platform: `vbwd-plugin-meinchat-plus`,
`vbwd-fe-user-plugin-meinchat-plus`, `vbwd-fe-admin-plugin-meinchat-plus`
(visibility = private for now; iOS NOT built — separate app). **`@signalapp/libsignal-client`
is Node-native → used audited pure-JS `@noble`/`hash-wasm`/`cbor-x`.** fe-user
`plugins/meinchat-plus/src/crypto/`: X3DH + Double Ratchet (forward secrecy,
tamper-detect, fan-out, own-device decrypt), 256B padding, CBOR envelope matching
the server validator, Argon2id KEK, downgrade fail-closed, registration —
**26 vitest specs green, eslint clean**. fe-admin scaffold (device-key view, 3
specs). Recipes wired (`ci-status.sh`, `push-plugins.sh`).

**Store crypto wiring DONE & green 2026-05-30**
([`reports/14-...md`](reports/14-meinchat-store-crypto-wiring.md)): crypto-provider
seam (`meinchat/src/crypto/messageCryptoRegistry`); backend conversation
serializer emits `protocol`; `useMeinchatStore.sendText` routes e2e via the
provider (fail-closed without one) + `_hydrateE2eRows`/`_decryptInPlace` decrypt
e2e rows on read/SSE; `MeinchatPlusProvider` + `registerCryptoProvider` hook.
All gates green (backend meinchat/meinchat_plus `--full`; fe-user **102** specs).

**SessionStore (LAST crypto layer) DONE & green 2026-05-30**
([`reports/15-...md`](reports/15-meinchat-plus-session-store.md)): prekey-message
header carries X3DH init; `SessionManager.ensureOutbound` (X3DH-from-bundle,
sig-verified) + `establishInbound` (responder cold-start, same-SK proven);
provider cold-start wiring; ratchet serialize + **KEK-sealed IndexedDB**
persistence. **Full no-prior-session bidirectional round-trip green; fe-user 111
specs, eslint clean.** meinchat-plus crypto + session layer is end-to-end functional.

**Pairing flow DONE & green 2026-05-30**
([`reports/16-...md`](reports/16-meinchat-plus-pairing-flow.md)): `device-store.ts`
(device material sealed under KEK + unsealed salt) + `pairing.ts` —
`pairNewDevice`/`unlockDevice`/`isPaired`/`lock`/`saveSessions`. pair → send →
persist → unlock → receive **end-to-end green**; wrong passphrase →
`WrongPassphraseError`. fe-user **114 specs**, eslint clean. **The meinchat-plus
web crypto is feature-complete** (crypto + session + persistence + pairing).

**Vue glue building blocks DONE & green 2026-05-30**
([`reports/17-...md`](reports/17-meinchat-plus-vue-glue.md)): `usePairing` +
`PairingSheet.vue` + `useComposerPrecheck` + attachment transport
(`uploadAttachment`/`downloadAttachment` + `encryptAndUploadAttachment`/
`downloadAndDecryptAttachment`). fe-user **136 specs**, eslint clean; all exported
from `index.ts`. (vitest: no global `$t` — pass `global.mocks.$t` to mount.)

**App-level view wiring DONE & green 2026-05-30**
([`reports/18-...md`](reports/18-meinchat-plus-view-wiring.md)): meinchat UI seams
(`src/ui/conversationExtensions.ts` overlay + composer-precheck registries,
core-agnostic); `ConversationView` renders the overlay + runs the precheck
(guarded → meinchat-alone unaffected); meinchat-plus `SecureChatGate.vue` (pairing
prompt for e2e until ready; `saveSessions()` on tab-hide) + `activate()` registers
overlay/precheck. fe-user **145 specs**, eslint clean. **TEXT E2E IS NOW WIRED
END-TO-END** (pair via gate → encrypted send → decrypted read; Send disabled for a
device-less peer).

**Attachment image UI DONE & green 2026-05-30**
([`reports/19-...md`](reports/19-meinchat-plus-attachment-image-ui.md)): provider
`sendEncryptedImage` (client-resize → encrypt fullres → upload + local preview) +
`hydrateRow` (decrypt text THEN attachment IN ORDER → body + blob URLs);
`store.sendAttachment` e2e route (fail-closed) + `_hydrateE2eRows`/`_decryptInPlace`
use hydrateRow; `MessageBubble` renders e2e image from `attachmentUrls`. **v1 =
fullres only** (one ratchet msg/image; thumb desyncs the in-order ratchet). fe-user
**151 specs**, eslint clean. **meinchat-plus WEB CLIENT IS FEATURE-COMPLETE — text
+ image E2E work end-to-end through the UI.**

**Pending (HARDENING + ops only — NO feature work left):** (a) ratchet **in-order
only** → skipped-message-key cache (also re-enables e2e thumbnails) + crypto audit
before flipping repos public; signed-prekey rotation + multi-device.
(c) **git seed + push** the 3 repos — DEFERRED per user. (d) iOS reads
`attachments[]` (separate app). Spec:
[`done/s28-3b-...md`](done/s28-3b-meinchat-plus-signal-ratchet.md) §3.

---

### S28.3b backend persistence reference (DONE)

See [`reports/08-s28-3b-backend-persistence.md`](reports/08-s28-3b-backend-persistence.md).
Built (all on disk, plugins gitignored): 4 models + migration (alembic path
registered), 3 repos (one-time consume = `FOR UPDATE SKIP LOCKED`), device
directory + signed/one-time prekey services (Ed25519 verify, concurrent-consume
race spec green), policy/capability/`MarkDeliveryAttempted`/`E2eAwareRetentionPolicy`,
`ProtocolAwareCodec` (plain↔e2e dispatch so enabling never breaks plaintext),
6 device/prekey routes, full `on_enable`/`on_disable`. **49 unit + 7 integration
green; gate `--plugin meinchat_plus --full` GREEN; meinchat still 241/5.**

**The plugin is DORMANT** (not in `plugins.json`) — global enable is blocked
by a small **meinchat** change set (its own slice). Do THIS next:

1. meinchat negotiation/send route: populate `SendContext.expected_device_ids`
   from `IDeviceDirectory.lookup_active` (peer + sender's own devices) and
   accept `envelope_b64` for `e2e_v1` sends (spec §2.4). This unblocks the
   true client→server→client round-trip + the four §2.10 ciphertext assertions.
2. meinchat `scheduler.py`: resolve `IRetentionPolicy` from the registry
   (falling back to `ConfigRetentionPolicy`) so `E2eAwareRetentionPolicy`
   actually drives the prune.
3. Update meinchat oracles to expect `e2e_v1` when meinchat-plus is enabled
   (`test_default_registry_returns_plain` asserts exactly `{"server":
   ["plain"]}` today → would break on enable).
4. THEN add `meinchat_plus` to `plugins.json` (`enabled: true`) +
   `plugins/config.json`; run full meinchat + meinchat_plus suites together.
5. Then **S28.4** (attachment encryption) + the **fe-user web crypto**
   (libsignal client) + iOS S28.6/S28.7.

**`cbor2` image note:** rebuild BOTH `test` AND `test-integration` compose
services (separate images off the same Dockerfile.test) or Part C fails
`ModuleNotFoundError: cbor2`.

---

### Original S28.3b backend checklist (DONE — kept for reference)

Strictly TDD, in this order (spec source: `sprints/s28-3b-...md` §2.3–§2.10):

1. **4 models** in `plugins/meinchat_plus/meinchat_plus/models/`:
   `meinchat_plus_user_device_key`, `meinchat_plus_signed_prekey`
   (EXCLUDE one-active-per-device), `meinchat_plus_one_time_prekey`
   (partial unconsumed index), `meinchat_plus_message_delivery`
   (composite PK `(message_id, device_id)`). Tests build schema via
   `create_all`, so model `__table_args__` must carry the constraints; mirror
   the EXCLUDE/partial-index in the **migration** too.
2. **Migration** `migrations/versions/20260601_xxxx_create_meinchat_plus_tables.py`
   (down_revision = the meinchat-plus chain root; first migration of this
   plugin → chain off a stable existing head, e.g. `20260528_1100_meinchat_e2e`).
   Register the path in `alembic.ini` `version_locations`
   (add `plugins/meinchat_plus/migrations/versions`).
3. **Repos** — `device_repository.py`, `prekey_repository.py`,
   `message_delivery_repository.py` (`mark_fetched`,
   `all_addressed_devices_have_fetched`, `mark_delivered_to_all`).
4. **Services** — `UserDeviceKeyDirectory` (IDeviceDirectory impl),
   `signed_prekey_service` (verify signature against device identity key,
   rotation supersedes), `one_time_prekey_service` (bulk upload, **consume via
   `SELECT … FOR UPDATE SKIP LOCKED`** — see spec §2.8; the **concurrency race
   test** `test_concurrent_consume_returns_distinct_prekeys` is the headline,
   needs a real DB-session factory + `threading.Barrier`).
5. **Policy/capability/hook** — `BothPeersHaveDeviceKeys` (IConversationPolicy),
   `E2eV1Capability` (IConversationCapabilities), `MarkDeliveryAttempted`
   (IPostSendHook), and `E2eAwareRetentionPolicy` (IRetentionPolicy — exempts
   rows with `delivered_to_all_addressed_devices_at IS NULL`).
6. **Routes** (`routes.py`) — the 6 device/prekey endpoints in spec §2.8
   (`POST /me/devices`, `GET /users/<id>/devices`, `DELETE /me/devices/<id>`,
   `POST /me/prekeys/signed`, `POST /me/prekeys/one-time`,
   `GET /devices/<id>/prekey-bundle`). Wire blueprint in `get_blueprint`.
7. **Expand `on_enable`** to register all 6 impls; `on_disable` unregisters each.
8. **Integration round-trip** `tests/integration/test_e2e_round_trip.py` — the
   4 critical assertions (body IS NULL, no plaintext marker in envelope,
   envelope length % 256 == 0, downgrade → 409). Needs a thin Python libsignal
   wrapper to simulate the client.
9. **Enable the plugin** — add `meinchat_plus` to `plugins/plugins.json`
   (`enabled: true`) + `plugins/config.json` only **after** the above is green,
   then run the full meinchat + meinchat_plus suites together.

Then **S28.4** (attachment encryption — mirrors the codec pattern; new
`meinchat_attachment` child table). Then the **fe-user web crypto** (separate,
careful pass) + coordinate with the iOS agent on S28.6/S28.7.

## 4. Gotchas / conventions (learned today)

- **`cbor2` needs an image rebuild** (`make up-build` / `docker compose build test`)
  — it's in `requirements.txt` but was only installed inline for test runs.
- **Tests build schema via `db.create_all()`** (model-driven), NOT migrations —
  put constraints in model `__table_args__`; the migration is for prod + the
  CI up/down/up matrix oracle (not run locally).
- **Plugin dir == metadata name, underscores** (`mercado_pago`, `toss_payments`)
  → used `meinchat_plus` (not the spec's hyphenated `meinchat-plus`).
- **Plugin→plugin import is allowed** when declared in
  `PluginMetadata.dependencies` — meinchat_plus imports meinchat's ports.
- **flake8 gate is `--max-line-length=120`** (`bin/pre-commit-check.sh:174`),
  not 79. Run black with **explicit file paths** for a brand-new plugin dir
  (dir-level black skipped `plugins/meinchat_plus/` — pass the files).
- **`meinchat_plus` is dormant** (not in `plugins.json`) until §3.9.
- **`SendContext.expected_device_ids`** is the union of
  `IDeviceDirectory.lookup_active` for peer + **sender's own devices** (own-device
  decrypt, critical-review §C7).

## 5. Locked decisions (don't relitigate)

Client-side crypto only (server never holds keys/decrypts) · 256-byte padding ·
`FOR UPDATE SKIP LOCKED` prekey consume (no advisory-lock alt) · split
signed/one-time prekey tables · downgrade fail-closed (client refuses
non-`e2e_v1` when it demanded it) · delivery tracking via
`meinchat_plus_message_delivery` (one table powers prune + UX) · default-on at
v1 launch (no gating) · public repos from day one · 2d server / 10d client
retention. Full list: status.md "S28 decisions locked 2026-05-28".

## 6. Quality snapshot (today, end of day)

- meinchat: **241 specs / 5 skipped**, lint clean.
- meinchat_plus: **9 validator specs**, lint clean.
- Nothing committed; nothing deployed.
