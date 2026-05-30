# S32 — macOS rate-limit overrides (meinchat)

**Status:** PLANNED — 2026-05-28. Follow-up to [S26](s26-meinchat-rate-limits.md).
S26 added iOS overrides keyed off `X-Client-Platform: ios`. The Mac Catalyst
build sends `X-Client-Platform: macos`
(`vbwd-ios/.../APIClientConfig.swift:24`) but today defaults to the web
baseline because no `rate_macos_*` entries exist. This sprint adds them so
the macOS native client gets the same higher ceilings as iOS.
**Track:** independent. **Repo:** `vbwd-backend` (plugin `plugins/meinchat/`).
**Engineering requirements (BINDING):** TDD-first · NO OVERENGINEERING —
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

---

## 1. Goal
A macOS-build user (X-Client-Platform: macos) gets the same higher ceilings
as iOS. Web/Android unchanged. RateLimitPolicy's existing fall-through
behaviour means a missing `rate_macos_*` key drops to baseline — so this
is strictly additive.

## 2. Design
Mirror the iOS keys. The macOS UX is the same one-on-one chat; nothing
about Mac usage suggests different ceilings.

Add 8 keys to `DEFAULT_CONFIG`, `config.json`, and a new "Rate limits
(macOS overrides)" tab in `admin-config.json`:

```python
"rate_macos_new_conversation_per_window":   60,   "rate_macos_new_conversation_window_seconds":  3600,
"rate_macos_nickname_search_per_window":    90,   "rate_macos_nickname_search_window_seconds":   60,
"rate_macos_message_send_per_window":      120,   "rate_macos_message_send_window_seconds":      60,
"rate_macos_attachment_send_per_window":    30,   "rate_macos_attachment_send_window_seconds": 3600,
```

`RateLimitPolicy.limits_for("new_conversation", "macos")` already returns
`rate_macos_new_conversation_*` when present (resolution is generic
`rate_<platform>_<category>_*`). Zero code change to the policy.

## 3. TDD
3 new specs in `test_rate_limit_policy.py`:

1. `test_macos_override_wins_when_present` — explicit macOS keys → returns them.
2. `test_macos_falls_through_to_baseline_when_no_override` — macOS keys absent
   → falls through to web baseline (no crash, no iOS-bleed).
3. Plus update `test_default_config_includes_all_16_rate_keys` → 24 keys.
4. New admin-config tab assertion in `test_default_config.py`.

## 4. Files
| Action | Path |
| --- | --- |
| edit | `plugins/meinchat/__init__.py` — DEFAULT_CONFIG +8 keys |
| edit | `plugins/meinchat/config.json` — +8 schema entries |
| edit | `plugins/meinchat/admin-config.json` — new tab `rate-limits-macos` |
| edit | `plugins/meinchat/tests/unit/services/test_rate_limit_policy.py` — +2 specs |
| edit | `plugins/meinchat/tests/unit/test_default_config.py` — extend to cover macOS |

## 5. Acceptance
- 5 new/updated specs green; existing 30+ stay green.
- `bin/pre-commit-check.sh --full` green on vbwd-backend.
- macOS Mac Catalyst client gets 60 new conversations/h ceiling, same as iOS.
