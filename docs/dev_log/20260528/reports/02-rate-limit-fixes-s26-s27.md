# Report — Two 429 bugs on vbwd.cc, fixed (S26 + S27)

**Date:** 2026-05-28
**Reporter symptoms** (both clients, same human user):
1. iOS chat screen: `rate limit for 'new_conversation' exceeded — retry in 3129s`
   after opening ≈10 existing chats in an hour.
2. fe-user web (later, after S26 was scoped): same meinchat error on web.
3. fe-user web (after S26 implemented): a *different* error —
   `{error: "Rate limit exceeded", message: "10000 per 1 day"}` — and iOS
   showed the same.

Two distinct rate limiters were tripping. They share the family resemblance
("429 in chat") but live in different layers and need different fixes. Both
landed today as separate sprints.

---

## Bug 1 — Meinchat `new_conversation` counter on every chat-open (S26)

### Diagnosis
`POST /api/v1/messaging/conversations` at
`plugins/meinchat/meinchat/routes.py:410` is documented as "start-or-get" —
returning the existing conversation row when present, creating one only when
absent. The guard at line 414 counted **every** call against
`new_conversation` (10/h/user), so opening an *existing* chat 11× in an hour
locked the user out.

Both clients hit this because both mount a fresh ConversationView (or
ConversationViewModel) on every navigation and POST the endpoint to resolve
`peer_nickname → conv_id`:
- iOS: `vbwd-ios/.../ConversationViewModel.swift:46-54`.
- fe-user web: `vbwd-fe-user/plugins/meinchat/src/views/ConversationView.vue:81-83`.

Counter mechanics: `meinchat:rate:new_conversation:<user_id>` in Redis,
`INCR` runs *before* the limit check (`rate_limiter.py:95`), so blocked
attempts also burn a slot — but TTL doesn't reset (`expire` only fires at
`ttl < 0`, line 71), so the counter drains naturally over the hour. That's
why "3129s" was visible in the user's screenshot.

### Fix (sprint plan: `docs/dev_log/20260528/sprints/s26-meinchat-rate-limits.md`)
Three additive edits in `plugins/meinchat/`:
1. **`ConversationService.find_between(user_a, user_b) → Optional[Conversation]`**
   — pure lookup, mirrors `start_or_get`'s pair-normalisation and DB query
   half without the create. `start_or_get`'s public contract is unchanged
   (Liskov-safe: `token_transfer_service.py:100` keeps working).
2. **`start_conversation` reordered** — call `find_between` first; if a row
   exists, return it with `X-Conversation-Existed: true` and **never touch
   the counter**. Only the create branch invokes `_enforce_rate`.
3. **`_enforce_rate(category)` is now policy-driven + platform-aware** — reads
   `(per_window, window_seconds)` from a new `RateLimitPolicy` keyed on
   `(category, X-Client-Platform)`. Zero literal numbers at call sites. 429
   responses now carry `X-Rate-Limit-Category`.

Plus a config layer:
- `__init__.py DEFAULT_CONFIG`, `config.json`, and `admin-config.json` gain
  16 flat rate-limit keys — 8 baseline + 8 iOS overrides, organised into
  two new admin tabs ("Rate limits (baseline)" / "Rate limits (iOS overrides)").
  Follows taro's flat-key + numeric-input + min/max convention.
- `RateLimitPolicy` resolution order: platform override → baseline → legacy
  flat keys (`message_rate_per_minute`, `attachment_rate_per_hour`, for
  back-compat) → hardcoded fail-safe. Unknown category → `ValueError`.
- iOS defaults bump the ceiling 6×: `new_conversation` 10/h → 60/h,
  `message_send` 30/min → 120/min, etc.

### What we explicitly did NOT do (NO OVERENGINEERING)
- No `(conv, created)` tuple return on `start_or_get` (would force every
  caller to unpack for zero benefit).
- No iOS or fe-user code change. After this fix the "POST on every mount"
  pattern is idempotent + free.
- No middleware, no decorator. No DB / migration / Redis schema change.
- No nested-object editing in admin-config — flat keys match taro
  convention everywhere else in the project.

### TDD
38 new specs across:
- `tests/unit/services/test_rate_limit_policy.py` (NEW, 11 specs):
  resolution order, legacy back-compat, zero-guard, case-insensitive platform,
  unknown category raises, empty platform falls through.
- `tests/unit/services/test_conversation_service.py` (extended, 4 specs):
  `find_between` returns existing pair, returns `None` for unknown, never
  writes, raises on self-pair.
- `tests/unit/routes/test_start_conversation_rate_limit.py` (NEW, 8 specs):
  - `test_repeat_open_same_peer_never_429` — today's prod repro negation
    (100× POST to same peer = all 200).
  - `test_first_creates_to_10_distinct_peers_then_429` — anti-spam contract
    still works on real creates.
  - `test_mixed_existing_and_new_only_counts_new` — fetch-existing is free,
    even when interleaved with creates.
  - `test_ios_header_lifts_new_conversation_ceiling_to_60` — override
    applied.
  - `test_platform_header_case_insensitive` — `iOS` ≡ `ios`.
  - `test_shared_bucket_per_user_across_platforms` — single counter per
    `(user_id, category)`, ceiling differs per request.
  - `test_existing_response_header` — `X-Conversation-Existed: true` only
    on the existing-chat path.
  - `TestTokenTransferRegression` — `start_or_get` still returns
    `Conversation`, not a tuple.
- `tests/unit/test_default_config.py` (NEW, 5 specs): DEFAULT_CONFIG +
  config.json + admin-config.json schema guards.

---

## Bug 2 — Global Flask-Limiter at 10000/day per IP (S27)

After S26 stopped the meinchat-specific 429s, both clients hit a different
one with the body `{"error": "Rate limit exceeded", "message": "10000 per 1
day"}`. Message format is Flask-Limiter's, not meinchat's.

### Diagnosis
`vbwd/extensions.py:15-20`:

```python
limiter = Limiter(
    key_func=get_remote_address,                          # ← keyed by IP
    default_limits=["10000 per day", "2000 per hour"],    # ← global default
    storage_uri=get_redis_url(),
)
```

- Default applies to **every** route by default; only `vbwd/routes/auth.py`
  and `vbwd/routes/events.py` declare per-route overrides.
- Keyed by client IP. Web + iOS on the same wifi share one bucket;
  mobile-carrier NAT / office network / VPN exit-nodes share one bucket
  across users.
- 10000/day = 6.94 req/min average. Active app use (chat fetches, paging,
  inbox refresh, SSE → REST poll fallback, image loads) crosses this fast.

### Fix (sprint plan: `docs/dev_log/20260528/sprints/s27-lift-global-flask-limiter.md`)
Two additive edits, no contract changes:

1. **`vbwd/extensions.py`** — extracted `_global_default_limits() -> list[str
   | Callable[[], str]]` reading `RATELIMIT_DEFAULT_DAY` (default **100000**,
   10× lift) and `RATELIMIT_DEFAULT_HOUR` (default **20000**, 10× lift) from
   env. Zero disables a window (operator escape hatch). Non-integer crashes
   startup (fail-fast on deployment-config typos).
2. **`.env.example`** — documented the new vars plus the existing
   `RATELIMIT_STORAGE_URL` / `RATELIMIT_ENABLED` Flask-Limiter contracts
   (passed through unchanged).

### What we explicitly did NOT do (deferred to follow-ups)
- **Per-user JWT-keyed limiter.** The right long-term fix for NAT-shared
  buckets; planned as [S31](../sprints/s31-flask-limiter-per-user-keying.md).
  Requires decoding the JWT (without signature verification — it's a bucket
  label, not auth) in the keyfunc. 10× lift alone takes today's repro out
  of the 429 zone.
- **Admin-UI tunability.** This is an ops-level knob, not per-tenant. Env
  var + restart is the right control surface; setting it through fe-admin
  would force shipping the value into Flask-Limiter at request time (it
  reads at app init).
- **Route-level exemptions.** Tempting to mark high-traffic read paths
  `@limiter.exempt` since S26 already provides a per-user custom limiter
  for meinchat abuse vectors — but the lift is enough; defer to data.
- **No change to the 429 response shape** at `vbwd/app.py:317-340`. Prod
  clients (web + iOS) already parse `{error, message}` + the `Retry-After`
  header; respect Liskov on the wire contract.

### TDD
12 new/extended specs:
- `tests/unit/routes/test_global_rate_limit_env.py` (NEW, 9 specs): defaults
  when env unset, day/hour overrides, zero-disables-window, both-zero,
  non-integer raises `ValueError`, limiter picks up defaults at boot.
- `tests/unit/routes/test_rate_limiting.py` (extended, 3 specs):
  per-route overrides unchanged (auth 5000/min, events 100/min stay), 429
  body shape unchanged, `RATELIMIT_ENABLED: False` still disables.

---

## Result

**Quality gate — `bin/pre-commit-check.sh --full`:** GREEN
- Part A: Static Analysis (black + flake8 + mypy) — PASS
- Part B: Unit Tests — **2228 passed** in 81s (+50 from S26 + S27 vs.
  pre-session baseline of ~2178).
- Part C: Integration Tests — 366 passed, 3 skipped in 135s.

**End-to-end live proof** (running localhost api after `docker compose restart api`):

| check | result |
| --- | --- |
| `limiter.limit_manager.default_limits` at boot | `['100000 per 1 day', '20000 per 1 hour']` — lifted 10× |
| `_global_default_limits()` with `RATELIMIT_DEFAULT_DAY=5 RATELIMIT_DEFAULT_HOUR=3` | `['5 per day', '3 per hour']` — env wins |
| App built with `RATELIMIT_DEFAULT_DAY=5`; 7 × GET / | 5 × 302 OK → req 6: **429 with `message: "5 per 1 day"`** → req 7: 429 same → trip at env-defined cap, body shape preserved |
| Meinchat regression — open same peer 100× | all 200, zero quota burned (S26 test `test_repeat_open_same_peer_never_429`) |

**Acceptance against today's screenshots:**
- iOS `rate limit for 'new_conversation' exceeded` → fixed by S26.
- Web + iOS `Rate limit exceeded — 10000 per 1 day` → fixed by S27 (10× lift
  by default; env-tunable per instance).

---

## Files changed

S26 (all in `vbwd-backend/plugins/meinchat/`):
- `meinchat/services/rate_limit_policy.py` (NEW)
- `meinchat/services/conversation_service.py` (edit — add `find_between`)
- `meinchat/routes.py` (edit — reorder + `_enforce_rate(category)` becomes
  policy-driven; 4 call sites collapse to one-liners)
- `__init__.py` (edit — DEFAULT_CONFIG +16 keys)
- `config.json` + `admin-config.json` (edit — 16 entries + 2 new admin tabs)
- 4 test files (3 NEW, 1 extended)

S27 (`vbwd-backend/`):
- `vbwd/extensions.py` (edit — `_global_default_limits()` helper)
- `.env.example` (edit — document RATELIMIT_* vars)
- 2 test files (1 NEW, 1 extended)

No core agnosticism oracle touched. No DB migration. No fe / iOS code
change. No 429 response shape change.

---

## Deploy notes

**vbwd.cc** needs:
1. Pull S26 + S27 code (backend image rebuild).
2. **In the api service env block of the prod compose file** (per
   `feedback_never_mix_local_and_prod_compose`, this is the file the operator
   scp's to the VPS):
   ```yaml
   environment:
     - RATELIMIT_DEFAULT_DAY=100000   # or higher per traffic profile
     - RATELIMIT_DEFAULT_HOUR=20000
   ```
   Strictly optional — the new code carries these as defaults baked in, so
   omitting them yields the same numbers. Set them explicitly only to tune
   away from defaults.
3. `docker compose restart api` (Flask-Limiter reads defaults at app init).
4. Smoke: open the chat screen on web + iOS, refresh 15× — no 429. Create
   11 new conversations on a fresh test account in <1h — 11th should still
   return 429 with `X-Rate-Limit-Category: new_conversation` + `Retry-After`
   (S26 anti-spam contract on real creates).

**No commits made.** Per project memory (`feedback_no_commit_without_ask`),
all changes live on disk; awaiting explicit instruction to commit / push.

---

## Out of scope (follow-up candidates, not blockers)

- **[S31 — per-user keying for Flask-Limiter](../sprints/s31-flask-limiter-per-user-keying.md).**
  Replace `get_remote_address` with a keyfunc that prefers
  `f"user:{jwt.user_id}"`. Eliminates the NAT-shared-bucket bug class.
  Needed if the 10× lift turns out to be insufficient for shared-IP cohorts
  (corporate networks, mobile carrier CGNAT).
- **[S32 — macOS rate-limit overrides](../sprints/s32-macos-rate-limit-overrides.md).**
  Add `rate_macos_*` keys to meinchat so Mac Catalyst clients get the same
  ceilings as iOS.
- **[S33 — 429 telemetry](../sprints/s33-429-telemetry.md).**
  Structured WARN log on every limiter trip (both the meinchat custom +
  Flask-Limiter global) so the next "users hit the cap" report is
  `grep`-able instead of screenshot-driven.
- **[S34 — drop legacy meinchat config keys](../sprints/s34-drop-legacy-meinchat-rate-keys.md)**
  (DEFERRED — gated on S26 being live on every prod instance + one deploy
  cycle elapsing). Remove `message_rate_per_minute` /
  `attachment_rate_per_hour` from `RateLimitPolicy`'s legacy fall-through.
- **[S35 — iOS: cache conv_id from inbox + drop 429-retry loop](../sprints/s35-ios-cache-conv-id-drop-retry.md).**
  After S26 the POST is free; this avoids it entirely when the inbox row
  already carries the `conv.id`. Also removes
  `ConversationViewModel.swift:61-66` exp-backoff 429 retry — after S26
  a 429 on chat-open is a real error, not a transient to retry.
- **Exempt read paths from the global limiter** (not yet numbered). S26's
  per-user meinchat limiter already handles abuse for those routes; global
  IP-limiter on top is belt-and-suspenders. Defer to data — ship S31 first;
  if it makes the global limiter clearly redundant for authenticated
  routes, queue this then.
