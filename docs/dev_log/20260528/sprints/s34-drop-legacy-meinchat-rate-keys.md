# S34 — Drop legacy meinchat rate-limit config keys (DEFERRED)

**Status:** PLANNED — 2026-05-28. **DEFERRED — DO NOT IMPLEMENT YET.**
Gated on:
1. S26 being live in **every** production / customer instance.
2. **One full deploy cycle** elapsing without rate-limit regressions reported
   against meinchat.

Once both hold, this sprint removes the two pre-S26 flat keys that
`RateLimitPolicy` carries today only as a back-compat fall-through:
`message_rate_per_minute` and `attachment_rate_per_hour`.
**Track:** independent of S28 / S29 / S30. **Repo:** `vbwd-backend` (plugin
`plugins/meinchat/`). **Engineering requirements (BINDING):** TDD-first ·
NO OVERENGINEERING ·
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

---

## 1. Goal
Single source of truth for meinchat rate limits — only the
`rate_<category>_*` / `rate_<platform>_<category>_*` shape. No legacy
fallback path. Less code to read, fewer accidental reads-from-wrong-key
bugs.

## 2. Current state (after S26 ships)
- `plugins/meinchat/__init__.py DEFAULT_CONFIG` still carries
  `message_rate_per_minute: 30` and `attachment_rate_per_hour: 6` as
  back-compat for instances whose per-instance config was written before
  S26 introduced the new flat keys.
- `RateLimitPolicy._LEGACY_KEY_MAP`
  (`plugins/meinchat/meinchat/services/rate_limit_policy.py:41-44`) reads
  them as a 3rd-tier fallback when neither the platform override nor the
  baseline `rate_message_send_*` / `rate_attachment_send_*` pair is set.
- The S26 test `test_legacy_message_rate_per_minute_back_compat` +
  `test_legacy_attachment_rate_per_hour_back_compat` pin the behaviour.

## 3. Why deferred (do not run today)
The persisted per-instance config under `${VBWD_VAR_DIR}/plugins/` is what
each running api reads at boot — not the in-image `DEFAULT_CONFIG`. After
S26 deploys, an instance only picks up the new `rate_message_send_*` keys
when an operator clicks Save in the admin UI **or** the persisted config
is regenerated. Until every live instance has the new keys persisted,
dropping the legacy fallback turns ceilings to fail-safe defaults
silently — at best inconvenient, at worst quota-suppressing.

The defer gate is therefore behavioural, not a timer:
- Confirm `${VBWD_VAR_DIR}/plugins/meinchat-config.json` on every prod
  host contains the new `rate_message_send_per_window` (etc.) keys; OR
- Confirm operators re-saved the meinchat plugin settings on every
  instance after the S26 deploy.

Either path means the legacy fall-through is genuinely unreachable.

## 4. Design (when unblocked)
Three deletes:

1. **`plugins/meinchat/__init__.py`** — remove `message_rate_per_minute`
   and `attachment_rate_per_hour` from `DEFAULT_CONFIG`. Add a comment
   pointing at this sprint doc for the rationale.
2. **`plugins/meinchat/meinchat/services/rate_limit_policy.py`** — delete
   `_LEGACY_KEY_MAP`, delete the 3rd-tier fall-through in `limits_for`,
   tighten the docstring accordingly.
3. **`plugins/meinchat/tests/unit/services/test_rate_limit_policy.py`** —
   delete `test_legacy_message_rate_per_minute_back_compat` +
   `test_legacy_attachment_rate_per_hour_back_compat`. Replace with one
   spec asserting the path is gone:
   ```python
   def test_no_legacy_fallback(self):
       cfg = {"message_rate_per_minute": 50}
       policy = RateLimitPolicy(cfg)
       # legacy key alone no longer produces a tuned limit — falls to
       # hardcoded fail-safe default (30/min) instead.
       assert policy.limits_for("message_send", "web") == (30, 60)
   ```

## 5. TDD (RED first, when unblocked)
- Flip the two existing legacy specs from passing-as-fallback to
  passing-as-gone (one new spec, two deletes).
- Re-run the full meinchat test suite — no other spec should reference
  the legacy keys.
- `bin/pre-commit-check.sh --full` green.

## 6. Acceptance
- `DEFAULT_CONFIG` does not contain `message_rate_per_minute` or
  `attachment_rate_per_hour`.
- `RateLimitPolicy` has no `_LEGACY_KEY_MAP`; `grep -n "_LEGACY_KEY_MAP\|message_rate_per_minute\|attachment_rate_per_hour" plugins/meinchat/`
  returns empty (only the sprint doc + report mentions remain in `docs/`).
- All meinchat unit tests green.

## 7. Out of scope
- No change to the new-shape `rate_*` keys or the policy resolution order
  for them.
- No change to `RateLimiter` or its Redis counter shape.
- No change to admin-config.json (legacy keys never made it into the
  admin UI).

## 8. Pre-run checklist (paste into the running sprint doc when unblocked)
- [ ] Confirm S26 is live on every prod instance (image digest = post-S26).
- [ ] `for host in <list>; do ssh $host 'jq "keys" /var/loopai/vbwd/plugins/meinchat-config.json'; done` — every output includes `rate_message_send_per_window` and `rate_attachment_send_per_window`.
- [ ] One full deploy cycle elapsed since S26 went live without a meinchat-rate-limit ticket.
- [ ] Sign-off from the operator who maintains the customer instances.
