# Report 09 — S28.3b meinchat-wiring slice + global enable (full e2e round-trip)

**Date:** 2026-05-29
**Sub-sprint:** [S28.3b](../done/s28-3b-meinchat-plus-signal-ratchet.md) (completing it to "enabled & full round-trip")
**Follow-up to:** [report 08](08-s28-3b-backend-persistence.md) (meinchat-plus backend persistence).
**Commits:** none (plugins gitignored; meinchat is in vbwd-backend on disk).

## Why this slice

Report 08 left meinchat-plus **dormant** because completing the true
client→server→client round-trip + flipping the plugin on required touching
**meinchat itself** (the prior slice was "meinchat untouched"). The user
authorised the meinchat changes, so this slice wires the send/read/prune
paths through the S28.3a ports and enables the plugin.

## meinchat changes (all backward-compatible — meinchat-alone unaffected)

1. **`message_service.send_text` populates `SendContext.expected_device_ids`**
   — the union of the peer's active devices and the sender's own (own-device
   decrypt), each as the 16-byte UUID the client packs into the envelope
   slots. Empty for `plain` and for meinchat-alone (`NullDeviceDirectory`),
   so plaintext chat is byte-for-byte unchanged.
2. **`send_message` route accepts `envelope_b64`** for non-`plain`
   conversations (reads `conversation.protocol`, decodes the opaque base64,
   sends with `protocol_hint=protocol`); plain conversations still post `body`.
   Posting `body` to an e2e conversation is refused 400.
3. **`list_messages` route fires `IPostSendHook.on_sent(row, fetched_by=device)`**
   for returned e2e rows when the caller passes their own `device_id`
   (query param or `X-Device-Id`). A foreign/unknown id is ignored; a
   throwing hook is logged, never fails the read. This is what drives
   delivery tracking.
4. **`scheduler.run_retention_prune` resolves `IRetentionPolicy` from the
   registry** (falls back to `ConfigRetentionPolicy`), so meinchat-plus's
   `E2eAwareRetentionPolicy` actually governs the prune when enabled.

## meinchat-plus change

- **Delivery "all fetched" now counts CBOR envelope slots**, not seeded
  rows. Rows are created lazily on fetch (`mark_fetched`); `delivered_to_all`
  flips when the fetched-row count reaches the number of `per_recipient`
  slots in the (opaque) envelope. Dropped the unused `seed()`/`expected_device_ids`
  repo methods; unit specs updated to real CBOR envelopes.

## Enablement + oracle hardening

- `meinchat_plus` added to `plugins/plugins.json` (`enabled: true`) +
  `plugins/config.json` (DEFAULT_CONFIG).
- `meinchat/tests/conftest.py` now also imports `meinchat_plus` models so the
  device-directory tables exist when the (now-registered) directory is queried
  during meinchat specs (guarded `try/except ImportError` for the
  independent-repo posture).
- Hardened `test_default_registry_returns_plain` to set its own deterministic
  capability registry (reset → PlainCapability) instead of relying on global
  boot order — an enabled meinchat-plus also registers `E2eV1Capability` at
  boot. The other capability specs already self-managed their registry.

## Full e2e round-trip test (server contract)

`plugins/meinchat_plus/tests/integration/test_e2e_round_trip.py` drives the
real meinchat routes with an OPAQUE (no real crypto — that's the client's job)
256B-padded CBOR envelope and asserts the four §2.10 critical guarantees on
the stored row:

- `body IS NULL`, `protocol == 'e2e_v1'`, `envelope` present;
- the plaintext marker never appears in the persisted envelope;
- `len(envelope) % 256 == 0` (padding survived);
- two-device delivery: `delivered_to_all_addressed_devices_at` stays NULL
  after the first device fetches and flips once the second device fetches.

Plus a downgrade refusal (peer with no device → 409) carried over from the
route suite.

## Gate results

- `bin/pre-commit-check.sh --plugin meinchat_plus --full` → **GREEN**.
- `bin/pre-commit-check.sh --plugin meinchat --full` → **GREEN** (241/5;
  one black wrap auto-applied to `routes.py`; mypy notes on
  `resolve_first(Protocol)` are non-blocking for plugins and match the
  pre-existing `resolve_first(IBodyCodec)` pattern).
- Broad unit sweep (core + all plugins, one process, meinchat-plus enabled):
  **2653 passed, 5 skipped**, plus **4 failed + 14 errors** — all in
  `tests/unit/services/test_rbac_seeder.py`, `tests/unit/test_create_admin.py`,
  and `plugins/stripe/tests/test_payment_e2e.py`. **Confirmed pre-existing and
  unrelated to this change**: re-running that exact set with meinchat-plus
  *disabled* reproduces the identical `4 failed / 14 errors`. Root causes are
  cross-plugin full-suite pollution, not meinchat:
  - RBAC seeder/`create_admin` errors = teardown `DELETE FROM vbwd_role`
    hitting a `vbwd_user_roles` FK (test-isolation ordering).
  - stripe e2e = a MagicMock invoice left `PENDING` because other plugins'
    event-bus subscribers raise in the shared process
    (`SubscriptionActivatedHandler` has no `handle_activated`; ghrm/booking
    "Flask app not registered with this SQLAlchemy instance").
  These are out of scope for S28.3b (pre-existing test-infra debt) and do not
  affect the per-plugin gates, which are the sprint's done-criterion.

## What remains for S28.3b

- **fe-user web crypto** (`vbwd-fe-user-plugin-meinchat-plus`) — real
  libsignal client (X3DH + double-ratchet), passphrase-Argon2id KEK, CBOR
  envelope packing, downgrade fail-closed, composer precheck.
- **iOS** (`vbwd-ios-plugin-meinchat-plus`, S28.6/S28.7) — in progress by the
  iOS agent.
- Manual two-client smoke (web ↔ iOS, `tcpdump`-on-loopback ciphertext check).

Next sprint: **S28.4 — attachment encryption** (mirrors this codec/child-table
pattern).
