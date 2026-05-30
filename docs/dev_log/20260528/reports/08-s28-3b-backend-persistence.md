# Report 08 — S28.3b backend persistence (meinchat-plus device keys + prekeys + delivery)

**Date:** 2026-05-29
**Sub-sprint:** [S28.3b — meinchat-plus Signal ratchet](../sprints/s28-3b-meinchat-plus-signal-ratchet.md)
**Gate:** `bin/pre-commit-check.sh --plugin meinchat_plus --full` → **GREEN**
(Part A static, Part B unit, Part C integration all pass).
**Commits:** none (plugins are gitignored in vbwd-backend; code lives on disk).

## What shipped (handoff §3 steps 1–8)

The full **backend persistence layer** for meinchat-plus, strictly TDD,
in `vbwd-backend/plugins/meinchat_plus/`:

1. **4 models** (`meinchat_plus/models/`): `user_device_key`,
   `signed_prekey`, `one_time_prekey`, `message_delivery`. Constraints
   live in `__table_args__` (tests build schema via `create_all`):
   - signed-prekey "one active per device" → **partial unique index**
     `WHERE rotated_at IS NULL` (equivalent to the spec's `EXCLUDE
     (device_id WITH =)` for equality, but **no `btree_gist` dependency**).
   - one-time-prekey **partial unconsumed index**.
   - delivery **composite PK `(message_id, device_id)`** (plain `db.Model`,
     no surrogate id / version).
2. **Migration** `migrations/versions/20260601_1000_create_meinchat_plus_tables.py`
   (down_revision `20260528_1100_meinchat_e2e`) mirroring the model DDL,
   registered in `alembic.ini` `version_locations`.
3. **Repos** (`repositories/`): `device_repository`, `prekey_repository`
   (one-time consume via **`SELECT … FOR UPDATE SKIP LOCKED`**, BYTEA→bytes
   normalised), `message_delivery_repository` (`seed`, `mark_fetched`,
   `all_addressed_devices_have_fetched`, `mark_delivered_to_all`).
4. **Services**: `UserDeviceKeyDirectory` (IDeviceDirectory),
   `SignedPrekeyService` (Ed25519 signature verify via `cryptography`,
   injectable verifier; rotation supersedes), `OneTimePrekeyService`
   (bulk upload, atomic consume, low-water refill signal).
5. **Policy/capability/hook/retention**: `BothPeersHaveDeviceKeys`
   (IConversationPolicy, e2e-only veto — plain stays allow-all/Liskov),
   `E2eV1Capability` (IConversationCapabilities), `MarkDeliveryAttempted`
   (IPostSendHook — flips `delivered_to_all_addressed_devices_at`),
   `E2eAwareRetentionPolicy` (IRetentionPolicy — exempts undelivered e2e).
6. **`ProtocolAwareCodec`** — the single IBodyCodec meinchat-plus registers.
   meinchat resolves ONE codec for every send; this dispatches `plain →
   IdentityBodyCodec` / `e2e_v1 → SignalEnvelopeValidator`, so enabling the
   plugin never breaks plaintext chat. (Closes the coexistence gap the
   single-impl seam would otherwise have.)
7. **6 routes** (`routes.py`, gated on `check_plugin_enabled`): `POST
   /me/devices`, `GET /users/<id>/devices`, `DELETE /me/devices/<id>`,
   `POST /me/prekeys/signed`, `POST /me/prekeys/one-time` (+`X-Prekey-Low-Water`
   header), `GET /devices/<id>/prekey-bundle` (consumes one one-time prekey).
8. **`on_enable`/`on_disable`** register/unregister all six impls (Liskov —
   meinchat falls back to its identity/null defaults on disable).

## Tests (all green)

- **49 unit specs** + **7 integration specs** (real PG + real JWT auth).
- Headline: `test_concurrent_consume_returns_distinct_prekeys`
  (`threading.Barrier`, real session factory) — pins the forward-secrecy
  guarantee that two concurrent consumers get different prekeys.
- Integration covers the 6 routes end-to-end + negotiation: e2e_v1 accepted
  when both peers have devices; **downgrade refused with 409** when the peer
  has none (fail-closed).
- meinchat unchanged: **241 passed / 5 skipped**; meinchat + meinchat_plus
  together **290 passed / 5 skipped** (no registry cross-leakage).

## Deliberately deferred (with reasons)

- **Plugin stays DORMANT** (NOT in `plugins.json`). Enabling it globally
  registers `E2eV1Capability`, which would make meinchat's S28.3a oracle
  `test_default_registry_returns_plain` (asserts exactly `{"server":
  ["plain"]}`) fail. Flipping that on requires editing meinchat's oracle
  tests — a **meinchat change**, and this slice is "meinchat untouched"
  (spec §1/§7 SOLID-O). Route/integration specs activate the plugin
  hermetically via the `enabled_plugin` fixture (gate-patch + registry
  wiring + full teardown reset).
- **Full client-encrypt → server-store → client-decrypt round-trip**
  (the four ciphertext assertions: body NULL, no plaintext marker, %256
  padding, downgrade). The server-side codec contract is pinned by the
  validator unit specs, but exercising it through an actual *message send*
  needs meinchat's send route to populate `SendContext.expected_device_ids`
  (from `IDeviceDirectory.lookup_active`) and accept `envelope_b64` — again
  a meinchat change. Plus the real ratchet is a **client** concern
  (web/iOS plugins) needing a libsignal wrapper. Deferred to the
  meinchat-send-wiring follow-up + the fe-user/iOS crypto work.
- **`E2eAwareRetentionPolicy` wiring into the prune.** meinchat's
  `scheduler.py` hard-codes `ConfigRetentionPolicy` (doesn't resolve
  IRetentionPolicy from the registry yet). The policy is implemented +
  registered + unit-tested; making the scheduler resolve it from the
  registry is the meinchat one-liner that completes the seam.

## Follow-up to land before §3.9 "enable the plugin"

A small **meinchat** change set (its own slice, updating meinchat's oracles):
1. negotiation/send route populates `expected_device_ids` + accepts
   `envelope_b64`; 2. scheduler resolves `IRetentionPolicy` from the
   registry; 3. update `test_default_registry_returns_plain` /
   capabilities + negotiate oracles to expect `e2e_v1` when meinchat-plus
   is enabled. Then add `meinchat_plus` to `plugins.json` + `config.json`
   and run the full meinchat + meinchat_plus suites together.

## Gotchas hit (for the next session)

- **`cbor2` image rebuilds**: BOTH the `test` AND `test-integration`
  compose services need `docker compose build` — they are separate images
  off the same `Dockerfile.test`. Part C failed `ModuleNotFoundError:
  cbor2` until `test-integration` was rebuilt.
- **Session-scoped test DB keeps rows across specs** → integration peers
  use unique email + nickname (`uuid4().hex[:10]`).
- **`black` skips `plugins/`** (gitignored) → the gate's dir-level black
  passes vacuously; **flake8 `--max-line-length=120` is the real lint
  gate** and is clean.
- psycopg2 returns BYTEA as `memoryview` → repo normalises to `bytes`.
