# S28 — Phase 2 master: meinchat-plus E2E + iOS app track

**Parent strategy doc:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
**Phase 1:** [s28-phase1-retention-and-config.md](s28-phase1-retention-and-config.md) — retention prune + config + cache. Must ship + bake before phase 2 starts.
**Decided 2026-05-28 (S28 decision R2-Q2):** phase 2 ships *after*
phase 1 has been live for one prod deploy cycle.

This master inherits:
- The threat model in the strategy doc §1.6 (operator cannot read
  message bodies; what the operator still sees).
- The 11 locked decisions in the strategy doc §11.
- The 16 Q&A decisions logged in `status.md` §"S28 decisions locked
  2026-05-28".

---

## 1. Goal (user value, crypto layer)

With phase 2 live + meinchat-plus enabled:

1. **Body confidentiality.** Chat bodies are encrypted **client-side**
   under Signal-protocol sessions; server stores opaque envelopes.
   Sender + recipient fan-out (own + peer devices) happens on the
   client. Server has no Signal session store, no encryption code,
   no decryption code.
2. **Forward + post-compromise secrecy** via the double-ratchet (per
   Signal protocol).
3. **Async first-message delivery** via one-time prekeys consumed
   under `SELECT … FOR UPDATE SKIP LOCKED`.
4. **Padding** to 256-byte multiples — observer learns plaintext
   length only to ±256 bytes.
5. **Downgrade defence.** Client refuses any response with `protocol
   != "e2e_v1"` when it demanded `accepted_protocols: ["e2e_v1"]`.
6. **Sender can read own messages on a second device.** Fan-out
   includes sender's own active devices.
7. **Delivery + read receipts.** Message bubbles show 0/1/2 dots
   (WhatsApp-style) — backed by the `delivered_at` / `read_at`
   columns added in S28.3a + the `POST /messages/<id>/read` route.
8. **iOS pairing UX:** biometric primary (Face ID / Touch ID) with
   passphrase fallback for biometric reset + device restore (S28
   decision R1-Q3).
9. **iOS launch posture:** the new `vbwd-ios-plugin-meinchat-plus`
   ships **enabled at v1 launch** — no opt-in gating phase (S28
   decision R2-Q1).
10. **Open-source from day one.** The three new plugin repos
    (`vbwd-plugin-meinchat-plus`, `vbwd-fe-user-plugin-meinchat-plus`,
    `vbwd-ios-plugin-meinchat-plus`) are public from creation (S28
    decision R4-Q1).

## 2. Phase 2 sub-sprints

| # | Sub-sprint | Lives in | Depends on |
|---|---|---|---|
| 3a | [meinchat extension ports + schema concessions + capability endpoints](s28-3a-meinchat-extension-ports.md) | meinchat (backend) | Phase 1 complete (uses S28.0 config keys) |
| 3b | [`meinchat-plus` plugin (client-encrypts Signal ratchet + device directory + split prekey tables + delivery tracking)](s28-3b-meinchat-plus-signal-ratchet.md) | **new repos** (3): backend + fe-user + iOS | S28.3a |
| 4 | [Attachment encryption (client encrypts; new `meinchat_attachment` child table for dual fullres/thumb blobs)](s28-4-attachment-encryption.md) | meinchat + meinchat-plus | S28.3a + S28.3b |
| 6 | [iOS meinchat plugin update (capability discovery + at-rest cache + retention UI + **receipt dots**)](s28-6-ios-meinchat-app-update-plan.md) | `vbwd-ios-plugin-meinchat` | S28.0 (phase 1) + S28.3a (phase 2 schema for receipts) |
| 7 | [iOS meinchat-plus plugin (Signal client + biometric+passphrase pairing + downgrade fail-closed + **receipt dots reused**)](s28-7-ios-meinchat-plus-plugin-plan.md) | **new repo** `vbwd-ios-plugin-meinchat-plus` | S28.3b |

**Within phase 2:** strict sequential — 3a → 3b → 4. Per the
ship-now order, 6 + 7 land alongside the v1 launch (R2-Q1: default
on at launch).

## 3. Phase 2 acceptance

- **No plaintext in transit or at rest for e2e_v1 rows.**
  - `body IS NULL` for all e2e_v1 rows in `message`.
  - `envelope` column does NOT contain the plaintext marker bytes
    (pinned by the integration test's raw-SELECT assertion).
  - SSE event payload for e2e_v1 rows carries only the envelope.
- **Ciphertext length is padded to 256-byte multiples.**
- **Sender can decrypt own message on second device** (fan-out
  includes sender's own active devices).
- **Concurrent two-senders-to-same-offline-recipient consume
  distinct one-time prekeys** (forward-secrecy race spec, S28.3b §2.10).
- **Client refuses downgrade** when it demanded `["e2e_v1"]` and the
  response is `"plain"`.
- **Undelivered e2e_v1 rows survive the S28.1 prune** until every
  addressed device has fetched.
- **iOS biometric pairing** — happy path uses Face ID / Touch ID;
  biometric reset recovers via the passphrase fallback.
- **Receipt dots** render correctly across plain + e2e_v1 in both
  iOS + fe-user — 0/1/2 dots match `delivered_at` / `read_at`.
- **Disabling meinchat-plus** (per-instance via admin UI OR
  per-device via Settings) restores plain meinchat cleanly.
- **All 8 sub-sprint gates GREEN.**

## 4. Phase 2 risk register

- **Crypto bug at launch.** With "default-on at v1" (R2-Q1), a crypto
  bug is a release-blocker not a beta-rollback. Mitigations: the TDD
  spec set (≥ 40 backend + ≥ 23 iOS + the web specs in S28.3b §3.8),
  the critical-review revision absorbed into every sub-sprint, the
  open-source posture (R4-Q1) enabling external review pre-launch.
  External audit decision deferred (R3-Q1) — revisit when S28.3b is
  implementation-ready.
- **Public repo posture (R4-Q1)** means the implementation
  trajectory is visible. Mitigation: feature branches for WIP; PRs
  reviewable end-to-end before merge to `main`.
- **iOS biometric reset on real devices** — Face ID retraining
  invalidates the primary Keychain entry. The passphrase fallback
  recovers, but the user has to actually remember the passphrase.
  Mitigation: pairing UX prompts to write down / store in 1Password.
- **One-time prekey exhaustion at heavy use.** Default 100 with
  refill-at-20 → for a heavy user sending ~50 first-contacts/day, the
  refill cadence needs to keep up. S28.3b's "low-water mark" header
  drives the client refill. Monitor in prod.

## 5. Phase 2 engineering-requirements check

- **TDD-first.** Critical-review-found regressions each get a
  dedicated test that would fail if the regression returned.
- **DevOps-first.** Migration up-down-up oracle on every sub-sprint
  that touches schema. CI cold-start on every plugin repo.
- **NO OVERENGINEERING.** Six ports concretely consumed by
  meinchat-plus; six speculative ports dropped (12 → 6). One
  capability endpoint (was 3). No server-side Signal session store.
  No `IAttachmentCodec` port (S28.4 folded into the existing flow).
- **DRY.** One `NoDeviceKeysError` in meinchat shared by body + attach
  codecs. One delivery-tracking table for the prune predicate
  (per-device). One `message.delivered_at`/`read_at` for UI receipts
  (per-user, protocol-agnostic). One `EnvelopePacker` grammar across
  three implementations (server cbor2 / web cbor-x / iOS SwiftCBOR).
- **Core agnostic.** Phase 2 work lives in `plugins/meinchat/` +
  `plugins/meinchat-plus/` + the three new client plugin repos.

## 6. Phase 2 ship gate

Phase 2 starts ONLY when:

1. Phase 1 has been in prod (vbwd.cc + every customer instance) for
   one deploy cycle without retention regressions.
2. The S28 decision R3-Q1 audit posture is picked.
3. The `meinchat-plus` GitHub org repos are created (public, per
   R4-Q1).
4. The S28.3a → S28.3b → S28.4 → S28.7 sequencing is locked in
   project planning (concurrent iOS plugin work + backend work needs
   coordinated PR boundaries).

---

## Anchor

Inherits the binding engineering requirements at
[`_engineering_requirements.md`](_engineering_requirements.md).
Strategy / threat model / locked decisions live in
[`s28-meinchat-e2e-encryption-and-retention.md`](s28-meinchat-e2e-encryption-and-retention.md).
