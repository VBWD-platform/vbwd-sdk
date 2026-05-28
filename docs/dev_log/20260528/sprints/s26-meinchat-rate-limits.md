# S26 — Meinchat rate limits: count creates only + iOS overrides + admin-configurable

**Status:** PLANNED — 2026-05-28. Today on prod the chat screen shows
*"rate limit for 'new_conversation' exceeded — retry in 3129s"* on **both**
clients:
- iOS — `vbwd-ios/.../ConversationViewModel.swift:46-54` POSTs
  `/api/v1/messaging/conversations` on every chat-view mount.
- fe-user web — `vbwd-fe-user/plugins/meinchat/src/views/ConversationView.vue:81-83`
  does the same on every `onMounted`.

Backend route at `plugins/meinchat/meinchat/routes.py:414` calls
`_enforce_rate("new_conversation", per_window=10, window_seconds=3600)`
unconditionally, **before** `start_or_get` has decided whether a new row is
actually created. So opening 10 existing chats in an hour locks the user out.

This sprint merges what was drafted as s1 (iOS per-platform overrides) + s2
(count creates only) into one slice because they share the same code paths
(route, policy, plugin config). It also makes **all four** meinchat rate-limit
categories admin-configurable per instance (today `new_conversation` and
`nickname_search` are hardcoded; `message_send` and `attachment_send` read flat
keys).

**Track:** independent. **Repo:** `vbwd-backend` (plugin `plugins/meinchat/`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** —
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
Gate: `bin/pre-commit-check.sh --full` green on `vbwd-backend`.

---

## 1. Goal (user value)

1. **Opening an existing conversation never burns a `new_conversation` slot.**
   The today-screenshot repro (open `@lololo` 15× in a minute on web or iOS)
   returns 200 every time. Only **first-time** message to a peer counts.
2. **Native clients get higher ceilings** via `X-Client-Platform: ios` (already
   sent by `vbwd-ios-core/.../APIClientConfig.swift:22`; macos shipped too).
   Web baseline unchanged.
3. **Per-instance admin configuration.** All four meinchat rate limits
   (`new_conversation`, `nickname_search`, `message_send`, `attachment_send`)
   are tunable per environment in the admin UI — no redeploy needed.

Target defaults (subject to per-instance override):

| category           | web (per/window)      | iOS (per/window)        |
| ---                | ---                   | ---                     |
| `new_conversation` | 10 / 3600s            | 60 / 3600s              |
| `nickname_search`  | 30 / 60s              | 90 / 60s                |
| `message_send`     | 30 / 60s              | 120 / 60s               |
| `attachment_send`  | 6 / 3600s             | 30 / 3600s              |

## 2. Current flow (grounded)

- **Rate guard helper.** `_enforce_rate(category, per_window, window_seconds)`
  at `plugins/meinchat/meinchat/routes.py:158-172`. Today every call site
  passes literal numbers — no platform awareness, no admin config for two of
  the four categories.
- **Counter.** `RateLimiter.check` at
  `plugins/meinchat/meinchat/services/rate_limiter.py:86-97`. Key shape
  `meinchat:rate:<category>:<user_id>` (line 94). Redis `INCR` runs **before**
  the limit check; TTL doesn't reset on subsequent INCRs (the `expire` at
  `rate_limiter.py:71` only fires when `ttl < 0`) — so the counter drains
  naturally. We leave the limiter alone.
- **Create-vs-fetch decision** already lives in
  `ConversationService.start_or_get`
  (`plugins/meinchat/meinchat/services/conversation_service.py:35-46`): it
  calls `find_by_pair(low, high)` first and returns the existing row when
  present, else inserts. The route just needs to consult this before counting.
- **`X-Client-Platform` is already wired.** Backend reads it for payment
  redirects at `vbwd-backend/vbwd/plugins/payment_route_helpers.py:225`. No
  client change needed for either iOS or web.
- **Admin-config convention.** Plugins use **flat keys**, numeric inputs,
  grouped into tabs — see `plugins/taro/admin-config.json` (LLM Configuration /
  Session Configuration / Oracle Prompts) for the canonical pattern. No
  nested-object editing exists anywhere in the project — we follow that.

## 3. Design

Three additive changes in `plugins/meinchat/`. Nothing touched in core.

### 3.1 Service — narrow lookup-only port

`ConversationService.find_between(user_a, user_b) -> Optional[Conversation]`
(NEW, ~6 lines). Pure read. Same `order_pair` normalisation as `start_or_get`.
Keeps `start_or_get`'s existing `Conversation` return type unchanged so
`token_transfer_service.py:100` (which auto-creates the conv row for a
transfer) is **Liskov-safe** — no call-site adjustment.

```python
def find_between(self, user_a: UUID, user_b: UUID) -> Optional[Conversation]:
    low, high = order_pair(user_a, user_b)
    return self._repo.find_by_pair(low, high)
```

### 3.2 Policy — config-driven, platform-aware

New module `plugins/meinchat/meinchat/services/rate_limit_policy.py`:

```python
class RateLimitPolicy:
    """Resolve (per_window, window_seconds) for (category, platform).

    Pure: takes the merged plugin config dict. No Flask, no Redis.
    """
    _CATEGORIES = ("new_conversation", "nickname_search",
                   "message_send", "attachment_send")

    def __init__(self, config: dict) -> None: ...

    def limits_for(self, category: str, platform: str) -> tuple[int, int]:
        """Resolution order, first hit wins:
           1) rate_<platform>_<category>_per_window / _window_seconds
           2) rate_<category>_per_window / _window_seconds
           3) hardcoded built-in default (fail-safe — never zero)
        Unknown platform string → falls through to baseline.
        Unknown category → raises ValueError (typo guard)."""
```

Cached on `current_app` next to `_meinchat_rate_limiter` (`routes.py:142-155`).
Built once per app boot from the merged plugin config.

### 3.3 Route — reorder + use the policy

`plugins/meinchat/meinchat/routes.py` — `start_conversation`
(`:410-432`) becomes:

```python
@meinchat_bp.route("/api/v1/messaging/conversations", methods=["POST"])
@require_auth
def start_conversation():
    data = request.get_json(silent=True) or {}
    peer_nickname = data.get("peer_nickname")
    if not isinstance(peer_nickname, str) or not peer_nickname.strip():
        return jsonify({"error": "peer_nickname is required"}), 400

    target = NicknameRepository(db.session).find_by_nickname_ci(peer_nickname.strip())
    if target is None or target.banned or target.search_hidden:
        return jsonify({"error": f"'{peer_nickname}' not found"}), 404

    # Lookup-first: free path for "open existing chat".
    existing = _conversation_service().find_between(g.user_id, target.user_id)
    if existing is not None:
        response = jsonify(_serialize_conversation_for_user(existing, g.user_id))
        response.headers["X-Conversation-Existed"] = "true"
        return response, 200

    # Only here do we count against new_conversation quota.
    blocked = _enforce_rate("new_conversation")
    if blocked is not None:
        return blocked

    try:
        conv = _conversation_service().start_or_get(g.user_id, target.user_id)
        db.session.commit()
        return jsonify(_serialize_conversation_for_user(conv, g.user_id)), 200
    except SelfConversationError as exc:
        db.session.rollback()
        return jsonify({"error": str(exc)}), 400
```

And `_enforce_rate(category)` (`:158-172`) collapses to zero literals:

```python
def _enforce_rate(category: str):
    platform = (request.headers.get("X-Client-Platform") or "web").lower()
    per_window, window_seconds = _rate_limit_policy().limits_for(category, platform)
    try:
        _rate_limiter().check(category, user_id=g.user_id,
                              limit=per_window, window_seconds=window_seconds)
    except RateLimitExceeded as exc:
        response = jsonify({"error": str(exc)})
        response.status_code = 429
        response.headers["Retry-After"] = str(exc.retry_after_seconds)
        response.headers["X-Rate-Limit-Category"] = category
        return response
    return None
```

Call sites at `:287` (`nickname_search`), `:459` (`message_send`), `:497`
(`attachment_send`) reduce to `_enforce_rate("…")`. `grep -nE '(per_window|window_seconds)\s*=\s*[0-9]' plugins/meinchat/meinchat/routes.py`
returns empty.

### 3.4 Plugin config (`plugins/meinchat/__init__.py` — `DEFAULT_CONFIG`)

Add 16 flat keys (taro-style — flat scalars, numeric, easy to expose in admin
UI, no nested-object editing). Existing keys preserved.

```python
DEFAULT_CONFIG: Dict[str, Any] = {
    "nickname_ban_grace_period_days": 30,
    "message_rate_per_minute": 30,          # legacy — kept for back-compat
    "attachment_rate_per_hour": 6,          # legacy — kept for back-compat
    "attachment_max_bytes": 5 * 1024 * 1024,
    "attachment_max_dimension_px": 2048,
    "sse_heartbeat_seconds": 20,
    "sse_stream_token_ttl_minutes": 60,

    # Baseline (web + unknown platforms)
    "rate_new_conversation_per_window": 10,
    "rate_new_conversation_window_seconds": 3600,
    "rate_nickname_search_per_window": 30,
    "rate_nickname_search_window_seconds": 60,
    "rate_message_send_per_window": 30,
    "rate_message_send_window_seconds": 60,
    "rate_attachment_send_per_window": 6,
    "rate_attachment_send_window_seconds": 3600,

    # iOS overrides (selected when X-Client-Platform: ios)
    "rate_ios_new_conversation_per_window": 60,
    "rate_ios_new_conversation_window_seconds": 3600,
    "rate_ios_nickname_search_per_window": 90,
    "rate_ios_nickname_search_window_seconds": 60,
    "rate_ios_message_send_per_window": 120,
    "rate_ios_message_send_window_seconds": 60,
    "rate_ios_attachment_send_per_window": 30,
    "rate_ios_attachment_send_window_seconds": 3600,
}
```

Legacy `message_rate_per_minute` / `attachment_rate_per_hour` stay as defaults
for any existing instance still relying on them; `RateLimitPolicy` reads the
new keys first and falls through to the legacy keys only when the new keys
are missing **and** the category is `message_send` / `attachment_send`. Old
instances keep working unchanged through one deploy cycle, after which the
legacy keys can be deleted in a follow-up.

### 3.5 Explicit `config.json` (schema — exact content)

```json
{
  "debug_mode": {
    "type": "boolean",
    "default": false,
    "description": "Enable verbose debug logging for the meinchat backend plugin (live mode when off)"
  },
  "max_message_length": {
    "type": "integer",
    "default": 4000,
    "description": "Maximum number of characters allowed in a single chat message"
  },
  "image_max_size_bytes": {
    "type": "integer",
    "default": 5242880,
    "description": "Maximum allowed image attachment size in bytes (default: 5 MB)"
  },

  "rate_new_conversation_per_window":   { "type": "integer", "default": 10,   "description": "Baseline: max new-conversation creations per rolling window (web + unknown platforms). Counter increments only when a brand-new conversation row is created — opening an existing chat is free." },
  "rate_new_conversation_window_seconds":{ "type": "integer", "default": 3600, "description": "Baseline: rolling window length in seconds for new_conversation." },
  "rate_nickname_search_per_window":     { "type": "integer", "default": 30,   "description": "Baseline: max nickname-search calls per rolling window." },
  "rate_nickname_search_window_seconds": { "type": "integer", "default": 60,   "description": "Baseline: rolling window length in seconds for nickname_search." },
  "rate_message_send_per_window":        { "type": "integer", "default": 30,   "description": "Baseline: max messages sent per rolling window." },
  "rate_message_send_window_seconds":    { "type": "integer", "default": 60,   "description": "Baseline: rolling window length in seconds for message_send." },
  "rate_attachment_send_per_window":     { "type": "integer", "default": 6,    "description": "Baseline: max attachment uploads per rolling window." },
  "rate_attachment_send_window_seconds": { "type": "integer", "default": 3600, "description": "Baseline: rolling window length in seconds for attachment_send." },

  "rate_ios_new_conversation_per_window":   { "type": "integer", "default": 60,  "description": "iOS override: max new-conversation creations per rolling window when X-Client-Platform: ios." },
  "rate_ios_new_conversation_window_seconds":{ "type": "integer", "default": 3600, "description": "iOS override: rolling window length in seconds for new_conversation." },
  "rate_ios_nickname_search_per_window":     { "type": "integer", "default": 90,  "description": "iOS override: max nickname-search calls per rolling window." },
  "rate_ios_nickname_search_window_seconds": { "type": "integer", "default": 60,  "description": "iOS override: rolling window length in seconds for nickname_search." },
  "rate_ios_message_send_per_window":        { "type": "integer", "default": 120, "description": "iOS override: max messages sent per rolling window." },
  "rate_ios_message_send_window_seconds":    { "type": "integer", "default": 60,  "description": "iOS override: rolling window length in seconds for message_send." },
  "rate_ios_attachment_send_per_window":     { "type": "integer", "default": 30,  "description": "iOS override: max attachment uploads per rolling window." },
  "rate_ios_attachment_send_window_seconds": { "type": "integer", "default": 3600, "description": "iOS override: rolling window length in seconds for attachment_send." }
}
```

### 3.6 Explicit `admin-config.json` (UI schema — exact content)

Mirrors the taro pattern (flat keys, `inputType: number`, grouped tabs with
`min`/`max` guards so admins can't enter zero or absurd values).

```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        { "key": "debug_mode", "label": "Debug mode", "component": "checkbox", "description": "Enable verbose debug logging. Disable in production (live mode)." },
        { "key": "max_message_length", "label": "Max message length (characters)", "component": "input", "inputType": "number", "min": 100, "max": 20000 },
        { "key": "image_max_size_bytes", "label": "Max image attachment size (bytes)", "component": "input", "inputType": "number", "min": 1024, "max": 52428800 }
      ]
    },
    {
      "id": "rate-limits-baseline",
      "label": "Rate limits (baseline)",
      "fields": [
        { "key": "rate_new_conversation_per_window",    "label": "New conversation — max per window",    "component": "input", "inputType": "number", "min": 1, "max": 10000, "description": "Counter only increments when a brand-new conversation row is created. Opening an existing chat is free." },
        { "key": "rate_new_conversation_window_seconds","label": "New conversation — window (seconds)",  "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_nickname_search_per_window",     "label": "Nickname search — max per window",     "component": "input", "inputType": "number", "min": 1, "max": 10000 },
        { "key": "rate_nickname_search_window_seconds", "label": "Nickname search — window (seconds)",   "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_message_send_per_window",        "label": "Message send — max per window",        "component": "input", "inputType": "number", "min": 1, "max": 100000 },
        { "key": "rate_message_send_window_seconds",    "label": "Message send — window (seconds)",      "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_attachment_send_per_window",     "label": "Attachment send — max per window",     "component": "input", "inputType": "number", "min": 1, "max": 10000 },
        { "key": "rate_attachment_send_window_seconds", "label": "Attachment send — window (seconds)",   "component": "input", "inputType": "number", "min": 1, "max": 86400 }
      ]
    },
    {
      "id": "rate-limits-ios",
      "label": "Rate limits (iOS overrides)",
      "fields": [
        { "key": "rate_ios_new_conversation_per_window",    "label": "iOS — New conversation max per window",    "component": "input", "inputType": "number", "min": 1, "max": 10000, "description": "Applied when the client sends X-Client-Platform: ios." },
        { "key": "rate_ios_new_conversation_window_seconds","label": "iOS — New conversation window (seconds)",  "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_ios_nickname_search_per_window",     "label": "iOS — Nickname search max per window",     "component": "input", "inputType": "number", "min": 1, "max": 10000 },
        { "key": "rate_ios_nickname_search_window_seconds", "label": "iOS — Nickname search window (seconds)",   "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_ios_message_send_per_window",        "label": "iOS — Message send max per window",        "component": "input", "inputType": "number", "min": 1, "max": 100000 },
        { "key": "rate_ios_message_send_window_seconds",    "label": "iOS — Message send window (seconds)",      "component": "input", "inputType": "number", "min": 1, "max": 86400 },
        { "key": "rate_ios_attachment_send_per_window",     "label": "iOS — Attachment send max per window",     "component": "input", "inputType": "number", "min": 1, "max": 10000 },
        { "key": "rate_ios_attachment_send_window_seconds", "label": "iOS — Attachment send window (seconds)",   "component": "input", "inputType": "number", "min": 1, "max": 86400 }
      ]
    }
  ]
}
```

### 3.7 What we explicitly DO NOT do (NO OVERENGINEERING)

- No change to `RateLimiter` or `RateLimitExceeded` — limiter contract is
  fine; we just feed it different numbers and call it less often.
- No `(conv, created)` tuple return on `start_or_get` — would force every
  existing caller to unpack for zero benefit. The route uses `find_between`.
- No iOS code change. iOS already sends `X-Client-Platform: ios`. The
  "POST on every chat-mount" anti-pattern becomes harmless after §3.3.
- No fe-user code change. After §3.3 the web POST is idempotent + free.
- No middleware, no decorator, no new platform-detection abstraction.
- No nested config objects — flat keys + numeric inputs, matching the
  established convention (see `plugins/taro/admin-config.json`).
- No DB schema change, no migration, no Redis schema change. Counter keys
  remain `meinchat:rate:<category>:<user_id>` — shared per user across
  platforms (only the ceiling varies per request); avoids the
  switch-device-to-game-the-quota vector.

### SOLID / DI / DRY / Liskov

- **SRP:** `find_between` does lookup; `start_or_get` does lookup-then-create;
  `RateLimitPolicy` resolves numbers; `RateLimiter` counts and decides;
  `_enforce_rate` is the HTTP glue.
- **OCP:** new platform (e.g. macOS) = add `rate_macos_*` keys in config; no
  code change beyond `_PLATFORMS` whitelist. New category = one config row
  + one `_enforce_rate(cat)` call.
- **DRY:** literal `(10, 3600)` / `(30, 60)` / `(30, 60)` / `(6, 3600)` tuples
  disappear from routes — single source of truth is the plugin config.
- **Liskov:** `start_or_get`'s return type is unchanged → `token_transfer` and
  every other caller unaffected. `RateLimiter.check` signature unchanged.
- **DI:** `RateLimitPolicy` constructed once per app from merged config; route
  resolves via cached `_rate_limit_policy()` factory next to
  `_rate_limiter()` / `_event_bus()`.
- **Core agnostic:** all changes live in `plugins/meinchat/`. Agnosticism
  oracles unaffected.

## 4. TDD (RED first)

All tests under `plugins/meinchat/tests/unit/`. No Redis required —
`InMemoryCounterBackend` (`rate_limiter.py:31`) is used in tests.

### 4.1 `RateLimitPolicy` unit tests (NEW
`tests/unit/services/test_rate_limit_policy.py`)

1. `test_baseline_for_web_platform` — `limits_for("new_conversation", "web") == (10, 3600)`.
2. `test_baseline_for_unknown_platform` — `platform="android"` →
   `(10, 3600)`; no crash, no override.
3. `test_ios_override_wins_when_present` — `platform="ios"` → `(60, 3600)`.
4. `test_ios_falls_through_to_baseline_for_unconfigured_category` — drop the
   iOS keys for `nickname_search`; `limits_for("nickname_search", "ios")` →
   baseline `(30, 60)`.
5. `test_unknown_category_raises_value_error` — `limits_for("typo", "web")` →
   `ValueError` (prevents silent zero-locks).
6. `test_legacy_keys_back_compat` — config has only
   `message_rate_per_minute: 50` (no `rate_message_send_*`) →
   `limits_for("message_send", "web") == (50, 60)`. Same for
   `attachment_rate_per_hour`.
7. `test_zero_or_negative_values_rejected_at_construction` — defending the
   `min: 1` admin guard at the policy layer too (belt + suspenders).

### 4.2 `ConversationService.find_between` unit tests (extend
`tests/unit/services/test_conversation_service.py`)

8. `test_find_between_returns_existing_pair` — seed via `start_or_get(A, B)`;
   `find_between(A, B)` returns it; `find_between(B, A)` returns the same row.
9. `test_find_between_returns_none_for_unknown_pair` — fresh repo → `None`.
10. `test_find_between_never_writes` — counting fake repo: N calls on unknown
    pair → `save` invoked 0 times.
11. `test_find_between_self_raises` — same `SelfConversationError` guard.

### 4.3 Route integration tests (NEW
`tests/unit/routes/test_start_conversation_rate_limit.py`)

12. `test_repeat_open_same_peer_never_429` — POST to the same peer 100× →
    all 200, no 429. **Today's screenshot repro negation.** (Web — no
    `X-Client-Platform` header.)
13. `test_first_creates_to_10_distinct_peers_then_429` — POST to 10 distinct
    peers (10 slots used) → all 200; POST to an 11th → 429 with
    `Retry-After` header + `X-Rate-Limit-Category: new_conversation`.
14. `test_mixed_existing_and_new_only_counts_new` — 9 distinct new peers (9
    slots), then 50× re-open those 9 (0 slots), then 10th new peer (1 slot
    = 10), then 11th new peer → 429.
15. `test_existing_response_header` — second POST to same peer returns
    `X-Conversation-Existed: true`; first POST does not.
16. `test_ios_header_lifts_new_conversation_ceiling_to_60` — same flow as #13
    with `X-Client-Platform: ios` — 60 distinct peers OK, 61st → 429.
17. `test_platform_header_case_insensitive` — `X-Client-Platform: iOS`
    behaves like `ios`.
18. `test_shared_bucket_per_user_across_platforms` — same user does 5 web
    POSTs (5 distinct peers) then 6 iOS POSTs (6 more peers, 11 total) →
    all 200 (under iOS ceiling 60); then 5 more web POSTs (16 total) →
    16th web POST (peer #16) → 429 (web ceiling 10 exceeded). Then an iOS
    POST to a 17th peer → 200 (iOS ceiling 60 still not hit). Pins the
    "shared bucket, per-request ceiling" decision.

### 4.4 Token-transfer regression guard

19. `test_token_transfer_unaffected` — call the token-transfer endpoint
    between two users with no prior conversation; the auto-created row
    appears (via `token_transfer_service.start_or_get`). `start_or_get` still
    returns `Conversation` (not a tuple). The transfer doesn't touch the
    `new_conversation` quota. (Regression guard on the non-route caller.)

### 4.5 Plugin config tests (NEW `tests/unit/test_default_config.py` or
extend existing)

20. `test_default_config_includes_all_16_rate_keys` — `from plugins.meinchat
    import DEFAULT_CONFIG`; all 16 new keys present with the §3.4 values.
21. `test_config_json_documents_all_16_rate_keys` — load
    `plugins/meinchat/config.json`; each key has `type: "integer"`, sensible
    `default`, non-empty `description`.
22. `test_admin_config_json_has_rate_limit_tabs` —
    `plugins/meinchat/admin-config.json` contains tabs `rate-limits-baseline`
    + `rate-limits-ios`, each with 8 numeric fields, every field has `min` ≥
    1 and `max` set.

### 4.6 Live-prod negation (manual, after deploy)

Reproduce today's screenshot: open `@lololo` on web AND iOS, refresh / re-nav
15× in a minute → every response 200, no 429. Plus: create 11 brand-new
conversations on web in <1h → 11th returns 429 with `Retry-After` (anti-spam
ceiling still works for real creates).

Run order: red all → implement §3.1 → green #8–#11 → implement §3.2 → green
#1–#7 → implement §3.4–§3.6 + §3.3 → green #12–#22 → `--quick` then `--full`.

## 5. Files

| Action | Path |
| --- | --- |
| new   | `plugins/meinchat/meinchat/services/rate_limit_policy.py` |
| edit  | `plugins/meinchat/meinchat/services/conversation_service.py` — add `find_between` |
| edit  | `plugins/meinchat/meinchat/routes.py` — reorder `start_conversation`; `_enforce_rate(category)` reads platform + policy; 4 call sites become one-liners; add `X-Rate-Limit-Category` to 429 + `X-Conversation-Existed` on existing-chat path |
| edit  | `plugins/meinchat/__init__.py` — `DEFAULT_CONFIG` gains the 16 keys in §3.4 |
| edit  | `plugins/meinchat/config.json` — full content in §3.5 |
| edit  | `plugins/meinchat/admin-config.json` — full content in §3.6 |
| new   | `plugins/meinchat/tests/unit/services/test_rate_limit_policy.py` (§4.1) |
| edit  | `plugins/meinchat/tests/unit/services/test_conversation_service.py` — §4.2 |
| new   | `plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py` (§4.3) |
| edit  | `plugins/meinchat/tests/unit/test_default_config.py` (or new) — §4.5 |

No core file touched. No migration. No fe / iOS code change.

## 6. Acceptance

- Today's prod repro returns 200 every time: open `@lololo` 15× in a minute
  on **both** web and iOS.
- An iOS user can create 60 brand-new conversations in an hour without 429;
  a web user is still capped at 10 (verified by tests #13 + #16).
- All four meinchat rate-limit categories are editable in the fe-admin
  "Meinchat plugin settings → Rate limits (baseline)" / "Rate limits (iOS
  overrides)" tabs; saving + the next request honours the new value (no
  restart needed — verify against the existing per-instance plugin-config
  reload path).
- `_enforce_rate("new_conversation", ...)` is **only** called on the create
  branch of `start_conversation`; `grep -n '_enforce_rate("new_conversation"'
  plugins/meinchat/meinchat/routes.py` returns one line, inside `if existing
  is None` (or the equivalent "create path" block).
- `grep -nE '(per_window|window_seconds)\s*=\s*[0-9]'
  plugins/meinchat/meinchat/routes.py` returns empty — zero literals.
- All 22 new/extended tests green. `bin/pre-commit-check.sh --full` green on
  `vbwd-backend`. Plugin agnosticism oracle unaffected. `token_transfer`
  tests unchanged.
- 429 responses carry `Retry-After` + `X-Rate-Limit-Category`. 200
  "existing-chat" responses carry `X-Conversation-Existed: true`.

## 7. Out of scope (follow-ups, not blockers)

- **iOS `conv_id` caching.** After this sprint the chat-mount POST is free,
  so caching the inbox-row's `conv_id` and going straight to
  `GET /messaging/conversations/<id>/messages` is pure perf polish.
- **iOS retry-on-429.** `ConversationViewModel.swift:61-66` exp-backoff
  retries on 429 — safe after this sprint (won't fire on chat-mount) but
  still worth removing.
- **macOS ceiling.** `X-Client-Platform: macos` is sent by the Mac Catalyst
  build; defaults to web baseline in this sprint. Add `rate_macos_*` keys
  when the macOS client is in user hands.
- **Per-IP / unauthenticated buckets.** Current keys are per-user-id; any
  future anonymous endpoint needs a separate bucket.
- **DELETE / archive of conversations.** Once delete lands, `find_between`
  should treat archived rows as "exists" (so a re-open doesn't burn a slot).
- **Drop legacy `message_rate_per_minute` / `attachment_rate_per_hour`** in
  the deploy cycle after this one (when every instance has the new keys).
