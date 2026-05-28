# S26 — Meinchat rate limits — COMPLETE

**Date:** 2026-05-28
**Sprint:** [`../sprints/s26-meinchat-rate-limits.md`](../sprints/s26-meinchat-rate-limits.md)
**Repo:** `vbwd-backend` (`plugins/meinchat/`)
**Gate:** `bin/pre-commit-check.sh --quick` green; **32/32 sprint tests pass**.

---

## 0. Outcome

The prod regression that triggered the sprint —
*"rate limit for 'new_conversation' exceeded — retry in 3129s"* on opening
an **existing** chat on both web and iOS — is closed at the source. The
route now consults `ConversationService.find_between` first and only
counts against the `new_conversation` quota when a brand-new row is
actually inserted. iOS gets a higher ceiling via
`X-Client-Platform: ios`. All four meinchat rate-limit categories are
now per-instance admin-configurable.

| Sprint goal | Status |
|---|---|
| Opening an existing chat never burns a `new_conversation` slot | ✅ test `test_repeat_open_same_peer_never_429` green |
| iOS ceiling (60 / hr for new_conversation) lifted via `X-Client-Platform` | ✅ test `test_ios_header_lifts_new_conversation_ceiling_to_60` green |
| All 4 categories admin-configurable per instance | ✅ `config.json` + `admin-config.json` shipped with 16 keys + 16 numeric form fields |
| Zero numeric literals in `routes.py` `_enforce_rate` call sites | ✅ grep `(per_window\|window_seconds)\s*=\s*[0-9]` returns empty |
| Legacy `message_rate_per_minute` / `attachment_rate_per_hour` keep working for older instances | ✅ test `test_legacy_keys_back_compat` green; fallback covered in `_LEGACY_KEY_MAP` |

---

## 1. What shipped

### 1.1 New service — `RateLimitPolicy` (~90 LOC)

`plugins/meinchat/meinchat/services/rate_limit_policy.py` — pure
config-resolving class. No Flask, no Redis. Built once per app from the
merged plugin config.

```python
class RateLimitPolicy:
    def limits_for(self, category: str, platform: str) -> tuple[int, int]:
        """Resolution order, first hit wins:
           1) rate_<platform>_<category>_per_window / _window_seconds
           2) rate_<category>_per_window / _window_seconds
           3) legacy flat keys (message_rate_per_minute, attachment_rate_per_hour)
           4) hardcoded built-in default (fail-safe — never zero)
        """
```

Rejects unknown categories with `ValueError` (typo guard), and zero /
negative values at construction (belt-and-braces against bad admin
input even though `admin-config.json` `min: 1` already gates it).

### 1.2 `ConversationService.find_between` (~6 LOC)

`plugins/meinchat/meinchat/services/conversation_service.py:50`. Pure
read; same `order_pair` normalisation as `start_or_get`. No write side
effects (verified by `test_find_between_never_writes`).
`start_or_get` return type unchanged → `token_transfer_service`
unaffected (verified by `test_start_or_get_return_type_is_conversation`).

### 1.3 Route reorder — `start_conversation`

`plugins/meinchat/meinchat/routes.py` — `start_conversation`:
1. Validate `peer_nickname` → 400 if missing.
2. Resolve nickname → 404 if banned / hidden / missing.
3. **`find_between(g.user_id, target.user_id)`** — if returns a row,
   serialise and return 200 + `X-Conversation-Existed: true`. **No
   `_enforce_rate` call on this path.**
4. Otherwise `_enforce_rate("new_conversation")` → 429 if exceeded.
5. `start_or_get(...)` to insert + commit, return 200 (no header).

The four `_enforce_rate` call sites are now one-liners:
- `routes.py:297` — `_enforce_rate("nickname_search")`
- `routes.py:450` — `_enforce_rate("new_conversation")` (create branch only)
- `routes.py:486` — `_enforce_rate("message_send")`
- `routes.py:519` — `_enforce_rate("attachment_send")`

`_enforce_rate` itself (`:159-184`) reads `X-Client-Platform`,
delegates to `RateLimitPolicy.limits_for(...)`, calls
`RateLimiter.check`, returns a 429 response (with `Retry-After` +
`X-Rate-Limit-Category` headers) or `None` for "go ahead".

### 1.4 Plugin config — 16 new flat keys

`plugins/meinchat/__init__.py::DEFAULT_CONFIG` — gained the 8 baseline
+ 8 iOS rate-limit keys per the sprint §3.4. Pre-S26 flat keys
(`message_rate_per_minute`, `attachment_rate_per_hour`) preserved as
back-compat fallback for instances that haven't deployed yet.

`plugins/meinchat/config.json` — JSON schema for all 16 keys plus the
existing `debug_mode`, `max_message_length`, `image_max_size_bytes` —
each with `type: "integer"`, default, description.

`plugins/meinchat/admin-config.json` — 3 admin-UI tabs (`general`,
`rate-limits-baseline`, `rate-limits-ios`) with 3 + 8 + 8 numeric
fields. Every field has `min: 1` + sensible `max`, matching the taro
plugin's conventional admin-config shape.

### 1.5 Tests — 32 of them, all green

| Suite | Count | Coverage |
|---|---|---|
| `tests/unit/services/test_rate_limit_policy.py` | 7 | resolution order, unknown category, unknown platform, legacy fallback, zero-value rejection |
| `tests/unit/services/test_conversation_service.py` (extended) | 4 of 4 new | `find_between` round-trip + Self guard + write-free guarantee |
| `tests/unit/routes/test_start_conversation_rate_limit.py` | 8 + 1 token-transfer regression | repro negation (open same peer 100× → 0 × 429); 10 → 11th peer ceiling; mixed new+existing only counts new; iOS ceiling of 60; case-insensitive platform header; shared bucket across platforms with per-request ceiling; existing-chat response header |
| Existing meinchat tests | 12 | re-verified; nothing regressed |

The shared-bucket test (`test_shared_bucket_per_user_across_platforms`)
specifically pins the decision noted in sprint §3.7: counter keys
remain per-user across platforms — only the **ceiling** varies per
request — so a user can't game the quota by toggling
`X-Client-Platform`.

---

## 2. What was explicitly NOT done (NO OVERENGINEERING)

Followed the sprint §3.7 don't-do list verbatim:

- **No change to `RateLimiter` / `RateLimitExceeded`** — limiter
  contract is fine; we just feed it different numbers and call it
  less often.
- **No `(conv, created)` tuple return** on `start_or_get` — would
  force every existing caller to unpack for zero benefit. The route
  uses `find_between` as the sprint specified.
- **No iOS code change.** iOS already sends `X-Client-Platform: ios`.
  The "POST on every chat-mount" anti-pattern is now harmless because
  the POST is free when the chat exists.
- **No fe-user code change.** Same reasoning.
- **No middleware, no decorator, no new platform-detection
  abstraction.** Platform read inline in `_enforce_rate` (3 lines).
- **No nested config objects** — flat keys + `inputType: number`,
  matching the established taro convention.
- **No DB schema change, no migration, no Redis schema change.**
  Counter keys remain `meinchat:rate:<category>:<user_id>` — shared
  per user.

---

## 3. SOLID / DI / DRY / Liskov / clean / core-agnostic

- **SRP** — `find_between` does lookup; `start_or_get` does
  lookup-then-create; `RateLimitPolicy` resolves numbers;
  `RateLimiter` counts; `_enforce_rate` is the HTTP glue. Each does
  one thing.
- **OCP** — adding a new platform (e.g. macOS) = add `rate_macos_*`
  keys in config + extend `_PLATFORMS` whitelist; no code change in
  routes or anywhere else. Adding a new category = one config row +
  one `_enforce_rate(cat)` call.
- **DRY** — literal tuples `(10, 3600)` / `(30, 60)` / `(30, 60)` /
  `(6, 3600)` are gone from `routes.py`. Single source of truth is
  the plugin config (per-instance overridable). Oracle confirmed:
  `grep -nE '(per_window|window_seconds)\s*=\s*[0-9]'
  plugins/meinchat/meinchat/routes.py` → empty.
- **Liskov** — `start_or_get`'s return type unchanged →
  `token_transfer_service:100` (auto-creates conv row for a transfer)
  unaffected. `RateLimiter.check` signature unchanged.
- **DI** — `RateLimitPolicy` constructed once per app from the merged
  plugin config; cached on `current_app` next to `_meinchat_rate_limiter`.
- **Core agnostic** — every file lives under `plugins/meinchat/`.
  Agnosticism oracle (`tests/unit/test_core_agnosticism.py`)
  unaffected.

---

## 4. Acceptance gate

| Criterion | Status |
|---|---|
| `pytest plugins/meinchat/tests/unit/services/test_rate_limit_policy.py` (7 tests) | ✅ all pass |
| `pytest plugins/meinchat/tests/unit/services/test_conversation_service.py` (covers new `find_between`) | ✅ all pass |
| `pytest plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py` (9 tests) | ✅ all pass |
| 16 rate-limit keys present in `DEFAULT_CONFIG` | ✅ `grep -c '^    "rate_' plugins/meinchat/__init__.py` = 16 |
| `config.json` documents all 16 keys with integer type | ✅ |
| `admin-config.json` has 3 tabs (general + 2 rate-limits), 16 numeric fields with `min: 1` | ✅ |
| Route `_enforce_rate("new_conversation")` called ONLY in the create branch | ✅ `routes.py:450`, inside `if existing is None` |
| Zero numeric literals in `_enforce_rate` call sites | ✅ grep returns empty |
| 429 carries `Retry-After` + `X-Rate-Limit-Category` | ✅ verified by `test_first_creates_to_10_distinct_peers_then_429` |
| 200 existing-chat carries `X-Conversation-Existed: true` | ✅ `routes.py:447`; verified by `test_existing_response_header` |
| `start_or_get` return type still `Conversation` (token-transfer regression) | ✅ verified by `test_start_or_get_return_type_is_conversation` |

---

## 5. Deploy implications

- **No DB migration.** No schema change anywhere.
- **No Redis schema change.** Counter keys unchanged; in-flight
  buckets keep counting through the upgrade.
- **No iOS or fe-user release.** All clients keep their existing
  POST-on-mount behaviour; the backend just stops penalising it.
- **Old-instance back-compat.** Any deployed meinchat instance still
  on the old `message_rate_per_minute` / `attachment_rate_per_hour`
  config keys continues to work (`RateLimitPolicy` falls through to
  them). Once every instance has rolled the new keys, the legacy
  fallback can be deleted in a follow-up.
- **Per-instance config rollout.** The new keys in `DEFAULT_CONFIG`
  apply automatically on container restart; admins can override per
  instance via the existing fe-admin meinchat settings page (which
  picks up the new tabs in `admin-config.json` without code change).

---

## 6. Manual live-prod verification checklist

After the next deploy:

1. Open `@lololo` on web; refresh 15× in a minute. **Every** request
   200 (was: first 10 OK, then 429 for 3129s). ✅ expected.
2. Same on iOS. ✅ expected.
3. As a web user with a fresh nickname, create 11 brand-new
   conversations within an hour. 1-10 → 200; 11th → 429 with
   `Retry-After` header. Anti-spam ceiling intact.
4. As an iOS user with a fresh nickname, create 60 brand-new
   conversations within an hour. 1-60 → 200; 61st → 429.
5. Open the fe-admin → meinchat plugin settings. Two new tabs:
   "Rate limits (baseline)" + "Rate limits (iOS overrides)". Edit
   `rate_new_conversation_per_window` to `5` → save → next 6th
   distinct new conversation gets 429.

---

## 7. Out of scope (sprint §7 — follow-ups, not blockers)

- iOS `conv_id` caching — chat-mount POST is free now, but caching
  inbox `conv_id` and going straight to
  `GET /messaging/conversations/<id>/messages` is pure perf polish.
- iOS retry-on-429 in `ConversationViewModel.swift:61-66` — won't
  fire on chat-mount anymore, but still worth removing.
- macOS ceiling — `X-Client-Platform: macos` falls through to web
  baseline; add `rate_macos_*` keys when the macOS client ships.
- Per-IP / unauthenticated rate buckets — current scheme is per-user;
  any future anonymous endpoint needs a separate bucket.
- DELETE / archive of conversations — once delete lands,
  `find_between` should treat archived rows as "exists" so re-open
  doesn't burn a slot.
- Drop legacy `message_rate_per_minute` / `attachment_rate_per_hour`
  in the next deploy cycle after this one.

---

## 8. Files touched

| Action | Path | Size |
|---|---|---|
| new   | `plugins/meinchat/meinchat/services/rate_limit_policy.py` | 90 LOC |
| edit  | `plugins/meinchat/meinchat/services/conversation_service.py` | + `find_between` (~6 LOC) |
| edit  | `plugins/meinchat/meinchat/routes.py` | reorder `start_conversation`; `_enforce_rate(category)` reads platform + policy; 4 call sites → one-liners; 429 response gains `X-Rate-Limit-Category` header; 200 existing-chat gains `X-Conversation-Existed` |
| edit  | `plugins/meinchat/__init__.py` | `DEFAULT_CONFIG` gains 16 keys; legacy keys preserved |
| edit  | `plugins/meinchat/config.json` | full content per sprint §3.5 |
| edit  | `plugins/meinchat/admin-config.json` | full content per sprint §3.6 |
| new   | `plugins/meinchat/tests/unit/services/test_rate_limit_policy.py` | 7 tests, 112 LOC |
| edit  | `plugins/meinchat/tests/unit/services/test_conversation_service.py` | + 4 tests for `find_between` |
| new   | `plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py` | 9 tests, 369 LOC |
| edit  | `plugins/meinchat/tests/unit/test_default_config.py` | covers new 16 keys |

**No core file touched. No migration. No fe / iOS code change.** Sprint
contract honoured.
