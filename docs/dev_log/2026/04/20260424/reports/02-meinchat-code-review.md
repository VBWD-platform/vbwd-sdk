# meinchat — code review

**Date:** 2026-04-29
**Sprint:** [57 — meinchat](../sprints/57-meinchat.md)
**Sprint status on disk:** **PLANNED** (header line 3) — not moved
to `done/` (`done/` does not exist for 20260424)
**Predecessor review:** [`01-meinchat-review.md`](./01-meinchat-review.md)
(2026-04-24)
**Methodology:** sprint-plan §-by-§ walk; runtime route inventory;
pre-commit gate; test collection.

---

## 1. Executive summary

**Backend grew from ~65% → ~85% complete since the 04-24 review.** The
token-transfer subsystem, all four Alembic migrations, and
`populate_db.py` — all flagged missing five days ago — are now in
place. Tests jumped from 100 → **111 passing**.

**Frontend remains 0%.** Both fe-user and fe-admin plugins still do
not exist anywhere on disk. That is the entire reason meinchat is
invisible in the user dashboard and admin moderation panel.

**Sprint is still NOT done.** Concrete gates failing:

| Gate | Status |
|---|---|
| Sprint doc moved to `done/` | ❌ — still in `sprints/`, header `Status: PLANNED` |
| `bin/pre-commit-check.sh --full` green | ❌ — flake8 fails on **6 unused imports** |
| ≥ 40 backend pytest cases (sprint DoD §1) | ✅ — **111 cases collected, 111 passing** |
| All three plugin repos exist | ❌ — **0 of 3 exist as standalone repos** |
| Demo instance smoke (alice ↔ bob loop on `vbwd.cc`) | ❌ — fe-user does not exist; cannot smoke |
| Admin moderation routes | ❌ — declared permissions, no routes |

**Bottom line:** the backend is production-quality engineering with
one working subsystem missing (admin routes) and a dirty pre-commit
gate (6 lint nits). The sprint cannot be closed without writing the
two frontend plugins and extracting all three to standalone repos.

---

## 2. Plan vs. reality, line-by-line

### 2.1 Backend file layout (sprint plan §Architecture, lines 92–135)

Plan vs disk:

```
                                            PLAN  ACTUAL  NOTE
meinchat/__init__.py                         ✅    ✅     Plugin class, Liskov-safe init
meinchat/meinchat/models/
  user_nickname.py                           ✅    ✅
  user_contact.py                            ✅    ✅
  conversation.py                            ✅    ✅
  message.py                                 ✅    ✅
  token_transfer.py                          ✅    ✅     46 LoC, ✅ added since 04-24
meinchat/meinchat/repositories/
  nickname_repository.py                     ✅    ✅
  contact_repository.py                      ✅    ✅
  conversation_repository.py                 ✅    ✅
  message_repository.py                      ✅    ✅
  token_transfer_repository.py               ✅    ✅     31 LoC, ✅ added since 04-24
meinchat/meinchat/services/
  slug_validator.py                          ✅    ✅
  nickname_service.py                        ✅    ✅
  contact_service.py                         ✅    ✅
  conversation_service.py                    ✅    ✅
  message_service.py                         ✅    ✅     262 LoC, includes post_system()
  attachment_service.py                      ✅    ✅
  sse_service.py                             ❌    ❌     Plan calls it sse_service.py;
                                                          functionality split across
                                                          event_bus.py + redis_event_bus.py
                                                          + stream_token.py + route handler
                                                          (5 files; intent matches plan)
  token_transfer_service.py                  ✅    ✅     127 LoC, ✅ added since 04-24
meinchat/meinchat/routes/                    ❌
  nickname.py                                       (collapsed into single routes.py)
  contacts.py                                       (collapsed)
  messaging.py                                      (collapsed)
  token_transfer.py                                 (collapsed)
meinchat/meinchat/routes.py                  ❌    ✅     609 LoC; works but breaks plan
meinchat/meinchat/events.py                  ✅    ❌     Not separately created; events
                                                          live inline in services
alembic/versions/                            ✅    ❌     Empty dir (legacy)
migrations/versions/                                ✅     Correct location per
                                                          feedback_plugin_migrations_in_plugin.md
  20260424_1000_meinchat_user_nickname.py    ✅    ✅
  20260424_1005_meinchat_user_contact.py     ✅    ✅
  20260424_1010_meinchat_conversation_…py    ✅    ✅
  20260424_1015_meinchat_token_transfer.py   ✅    ✅
populate_db.py                               ✅    ✅     ✅ added since 04-24
plugins.json patch                           ✅    ✅
config.json patch                            ✅    ✅
```

**Drift findings:**
1. `meinchat/meinchat/routes/` was supposed to be a **directory** with
   four sub-files (nickname.py / contacts.py / messaging.py /
   token_transfer.py). Actual implementation is one **flat file**
   (`routes.py`, 609 lines). The flat file is functional but breaks
   plan's modular split. Acceptable as-is — registering one Blueprint
   with absolute paths matches the plan's plugin-class spec
   (`get_url_prefix() == ""`); just a single-file vs split decision.
2. **`events.py`** — planned as a single file holding event types
   (`NicknameSetEvent`, `MessageSentEvent`, …). Actual events emitted
   inline from services via the event_bus's string topic API. Works,
   but typed event classes were a discipline aid; their absence means
   no compile-time check on event shape.
3. **`alembic/`** — empty dir at `vbwd-backend/plugins/meinchat/alembic/`
   is dead code. The actual migrations live at `migrations/versions/`
   per the new convention from `feedback_plugin_migrations_in_plugin.md`
   (added today, line 56 of MEMORY.md). Delete the orphan dir.

### 2.2 Plugin class (sprint §137–158)

`vbwd-backend/plugins/meinchat/__init__.py`:

| Spec (plan) | Actual |
|---|---|
| `version="1.0.0"` | **`version="0.1.0"`** ❌ |
| Liskov-safe `initialize(merged_config)` calling `super().initialize(merged)` | ✅ (line 44–48) |
| `get_blueprint() → meinchat_bp` | ✅ |
| `get_url_prefix() == ""` (absolute paths in routes) | ✅ |
| `on_enable() / on_disable()` no-ops | ✅ |

DEFAULT_CONFIG diff:
- Plan locked decisions implemented in code:
  - `nickname_ban_grace_period_days: 30` ✅
  - `message_rate_per_minute: 30` ✅
  - `attachment_rate_per_hour: 6` ✅
  - `attachment_max_bytes: 5 * 1024 * 1024` ✅
  - `attachment_max_dimension_px: 2048` ✅
  - `sse_heartbeat_seconds: 20` ✅
  - `sse_stream_token_ttl_minutes: 60` ✅

The plugin class declares **3 admin permissions** but routes for them
are absent (see §2.4).

### 2.3 Models (sprint §160–227)

Per-table diff (schema vs sprint plan §160-227):

**`user_nickname`** — present, includes `banned`, `banned_at`,
`search_hidden`, generated `nickname_ci`, prefix index, unique index.
✅ Full match.

**`user_contact`** — present with `owner_user_id`, `contact_user_id`,
`alias`, `note`, `pinned`, `added_at`, unique pair, self-add CHECK.
✅ Full match.

**`conversation`** — present with `participant_low_id` /
`participant_high_id` (LEAST/GREATEST canonicalisation),
`last_message_at`, `last_message_preview`, dual unread counters,
unique pair, self-pair CHECK. ✅ Full match.

**`message`** — present with `sender_id`, `sender_nickname`
(snapshot), `body`, `attachment_url`, `attachment_thumb_url`,
dimensions, `delivered_at`, `read_at`, `system_kind`. ✅ Full match.

**`token_transfer`** — present with `sender_user_id`,
`recipient_user_id`, `amount` (CHECK > 0), `note`, `executed_at`. ✅
Full match.

All four migrations follow the planned filenames + ordering
(20260424_1000 → 1005 → 1010 → 1015).

### 2.4 Routes (sprint §231–308)

**Live at runtime:** 17 routes from `app.url_map.iter_rules()`.

**User-facing:**
- `GET /api/v1/nickname/me` ✅
- `PUT /api/v1/nickname/me` ✅
- `GET /api/v1/nickname/search` ✅
- `GET /api/v1/nickname/<nickname>/card` ✅
- `GET /api/v1/contacts` ✅
- `POST /api/v1/contacts` ✅
- `PATCH /api/v1/contacts/<id>` ✅
- `DELETE /api/v1/contacts/<id>` ✅
- `GET /api/v1/messaging/conversations` ✅
- `POST /api/v1/messaging/conversations` ✅
- `GET /api/v1/messaging/conversations/<id>/messages` ✅
- `POST /api/v1/messaging/conversations/<id>/messages` ✅
- `POST /api/v1/messaging/conversations/<id>/messages/attachment` ✅
- `POST /api/v1/messaging/conversations/<id>/read` ✅
- `DELETE /api/v1/messaging/conversations/<id>/messages/<mid>` ✅
- `GET /api/v1/messaging/stream` ✅ (SSE)
- `POST /api/v1/messaging/stream/token` ✅
- `POST /api/v1/token-transfer` ✅ (added since 04-24)
- `GET /api/v1/token-transfer/history` ✅ (added since 04-24)

**Admin (sprint §240–244 + §492–499):**
- `POST /api/v1/admin/meinchat/nicknames/:id/ban` ❌ MISSING
- `POST /api/v1/admin/meinchat/nicknames/:id/unban` ❌ MISSING
- `GET /api/v1/admin/meinchat/conversations/:id` ❌ MISSING
- `GET /api/v1/admin/meinchat/transfers` ❌ MISSING

**Service support exists** for ban/unban —
`NicknameService.ban(user_id)` / `.unban(user_id)` are implemented
(`nickname_service.py:100-114`). They're just unreachable from HTTP.
The 3 admin permissions in `__init__.py` line 60-76 are declared but
**unenforceable**.

### 2.5 SSE design (sprint §277–302)

**Wire model:** sender → POST /messages → DB commit →
`event_bus.publish(f"user:{recipient}", payload)` → all `/stream`
subscribers fan-out. ✅ Implemented.

**Bonus over plan:** sprint says "Multi-worker → swap the
implementation to Redis pub/sub. Deferred." (§302). Code already has
**both** — `event_bus.py` (in-process) AND `redis_event_bus.py`
(cross-worker via Redis). Plugin auto-selects based on
`current_app.redis` presence. This is the right call: free
multi-worker scaling.

**Stream-token JWT:** `aud=meinchat-stream`, 60-min TTL, mintable via
authenticated `POST /stream/token`. ✅ Matches plan §300.

**Heartbeat:** every 20 s per `sse_heartbeat_seconds`. ✅ Configurable.

**Wire events** — plan §298 says `message`, `message_deleted`,
`read`, `token_transfer`, `heartbeat`. Code emits all five. ✅

### 2.6 Token transfer (sprint §304–313)

**Routes:** `POST /api/v1/token-transfer` and
`GET /api/v1/token-transfer/history` ✅

**Service:** `TokenTransferService.transfer()` with `SELECT FOR
UPDATE` row lock pattern.
([token_transfer_service.py](../../../vbwd-backend/plugins/meinchat/meinchat/services/token_transfer_service.py),
127 LoC.)

**System-message wire** (sprint §313: token transfer surfaces as a
`system_kind='token_transfer'` message in the same conversation):
`token_transfer_service.py:104` calls `message_service.post_system(
system_kind="token_transfer", …)`. ✅ Implemented.

**Method-specific TDD checkpoints (sprint §79–84):**
- `InsufficientTokensError`, no rows mutated ✅ (typed exception
  class, line 14 of service)
- Concurrent A→B / A→C with row lock — test
  `test_token_transfer_service.py::TestRejections` covers self,
  zero, negative, and float rejections; **concurrent two-thread
  test claimed in sprint plan §82 is NOT present** (no thread-spinning
  pytest). ⚠️ Gap.
- Self-transfer → `SelfTransferError(ValueError)` ✅
- Positive integer enforced ✅
- `TokenTransferredEvent` + dual-credit + ledger row in one
  transaction ✅

### 2.7 Tests (sprint §556 DoD; §571–578 test plan)

**Counts (collected today):**

| Layer | Plan target | Actual |
|---|---|---|
| Backend unit | ≥ 40 | **111** ✅ |
| Backend integration | "real DB end-to-end" | **0 — directory empty** ❌ |
| Frontend unit (Vitest) | conversational stores, useMessagingStream, etc. | **0 — fe-user does not exist** ❌ |
| Frontend E2E (Playwright) | alice↔bob full loop | **0** ❌ |

**Backend unit breakdown:**

```
test_attachment_service.py        8
test_contact_service.py          12
test_conversation_service.py      9
test_event_bus.py                 6
test_message_service.py          13
test_nickname_service.py         13
test_rate_limiter.py              5
test_slug_validator.py            8
test_stream_token.py              5
test_token_transfer_service.py    9
+ misc / collection deltas       23
TOTAL                           111
```

**Empty test dirs:**
- `tests/unit/repositories/` — empty (no `__init__.py` reads or
  filter_by tests against `MagicMock` session).
- `tests/unit/routes/` — empty (no Flask test-client coverage of
  401/403/404/429 paths).
- `tests/integration/` — empty (no real-DB end-to-end).

The 111 service-layer specs are thorough but every spec mocks the
repo. Repository SQL correctness, route auth wiring, and
end-to-end migration → seed → write → read are unverified.

### 2.8 Locked decisions (sprint §599–608)

| # | Decision | Code state |
|---|---|---|
| 1 | Free nickname change, no cooldown, no token cost | ✅ no `last_changed_at` column; service has no cooldown gate |
| 2 | Token-transfer minimum = positive integer ≥ 1 | ✅ DB CHECK + service `ValueError` on float/zero/negative |
| 3 | Attachment hard-deleted with parent message; no TTL | ✅ `message_service.delete_message` purges via IFileStorage.delete (verified by test_message_service.py) |
| 4 | Hard message delete on both sides, no tombstone, SSE `message_deleted` | ✅ delete route emits `message_deleted` event |
| 5 | Banned-nickname slug reclaim after grace period | ✅ `_ban_grace_elapsed` in nickname_service.py:118-124, lazy on PUT /nickname/me |
| 6 | Address book per-user private | ✅ `user_contact.owner_user_id` scopes every query |
| 7 | No live presence; "last seen" via `last_message_at` | ✅ no presence table; conversation row carries `last_message_at` |

All 7 locked decisions implemented faithfully.

### 2.9 Security posture (sprint §516–528)

| # | Item | Code state |
|---|---|---|
| 1 | Image: MIME sniff via Pillow, ≤ 5 MB pre-decode, ≤ 2048 px, EXIF stripped, re-encoded WebP | ✅ AttachmentService — verified by 8 unit tests (size, MIME, dimension, EXIF) |
| 2 | SSE `aud=meinchat-stream`, short-lived, revoke on logout | ⚠️ TTL + audience implemented; **revoke-on-logout (Redis revocation list) NOT verified in code** — `stream_token.py` has 5 tests but logout-side revoke is not present |
| 3 | Nickname enumeration: prefix-only, 30/min rate, exclude self/banned/hidden | ✅ rate limit at route line 209; service excludes per `search_prefix` |
| 4 | XSS: Vue auto-escape + `SafeLinkify.vue` | ❌ no fe-user → no SafeLinkify; deferred until UI exists |
| 5 | CSRF: JWT in Authorization header, no cookies | ✅ existing VBWD pattern, applies |
| 6 | SQL injection: SQLAlchemy parameterised; prefix uses text_pattern_ops + `LIKE :prefix \|\| '%'` | ✅ verified in nickname_repository |
| 7 | Per-user Redis rate limits + Retry-After | ✅ `_enforce_rate` in routes |
| 8 | Token transfer atomic: `SELECT FOR UPDATE` + dual-write + ledger in one tx | ✅ implemented; ⚠️ **no concurrent-thread integration test** (planned §82) |
| 9 | Self-ban returns 409 | ❌ admin route absent ⇒ check absent |

### 2.10 Observability (sprint §532–540)

Sprint plan promises 4 Prometheus counters:
- `meinchat_messages_sent_total{kind=...}` ❌
- `meinchat_sse_connections_gauge` ❌
- `meinchat_token_transfer_volume_total{direction}` ❌
- `meinchat_token_transfer_failures_total{reason}` ❌

**None implemented.** No `prometheus_client` imports anywhere in the
plugin. No `/metrics` registration. Operations is fully blind to this
plugin in production.

### 2.11 fe-user plugin (sprint §317–488)

```
$ find vbwd-fe-user/plugins -iname "*meinchat*"
(zero hits)
$ grep -rn "meinchat\|nickname" vbwd-fe-user/plugins --include="*.ts" --include="*.vue"
(zero hits)
```

**Nothing exists.** The whole §Frontend section of the sprint plan
(176 lines, lines 317–488) is unimplemented:
- 4 views (InboxView, ContactsView, ConversationView, NicknameSettingsView)
- 9 components (ConversationHeader, MessageBubble, MessageComposer,
  InboxRow, ContactRow, AddContactDialog, FindUserDialog,
  TokenTransferDialog, NicknameAvailabilityIndicator)
- 3 composables (useMessagingStream, useNicknameSearch, useImageAttach)
- 3 stores (useMeinchatStore, useContactsStore, useNicknameStore)
- `api.ts` thin wrappers
- 8 locales (en/de/es/fr/ja/ru/th/zh)
- Plugin manifest with `userNavRegistry.register({...})` for the
  `💬 Messages` sidebar entry

This is **the entire reason meinchat is invisible** in the
storefront. Backend works perfectly; nothing renders it.

### 2.12 fe-admin plugin (sprint §492–499)

```
$ find vbwd-fe-admin/plugins -iname "*meinchat*"
(zero hits)
```

**Nothing exists.** Plan calls for:
- Conversations inspector at `/admin/meinchat/conversations/:id`
- Nicknames list with ban/unban + search-hidden toggle
- Transfers paged audit log

### 2.13 Demo (sprint §503–513)

- `populate_db.py` ✅ exists, idempotent, seeds alice + bob, three
  messages, image attachment, read receipt, transfer of 10 tokens.
  ⚠️ flake8 flags an unused `result =` in line 41 (lint failure
  below).
- Demo instance enable on `vbwd.cc` ❌ — depends on fe-user existing.

### 2.14 Repos (sprint §564 — "all plugin code lives in its own repo")

| Repo | State |
|---|---|
| `vbwd-plugin-meinchat` | ❌ does not exist on GitHub; lives only in `vbwd-backend/plugins/meinchat/` |
| `vbwd-fe-user-plugin-meinchat` | ❌ does not exist anywhere |
| `vbwd-fe-admin-plugin-meinchat` | ❌ does not exist anywhere |

Direct violation of `feedback_plugins_always_in_own_repos.md`.

### 2.15 Pre-commit gate (sprint DoD §2)

`docker compose run --rm test ./bin/pre-commit-check.sh --plugin
meinchat --quick`:

```
[FAIL]  Part A: Static Analysis  ← flake8 fails on 6 files
[PASS]  Part B: Unit Tests       ← 111/111 green
FAILED: Static analysis errors must be fixed before commit
```

**Specific failures (all `F401 unused import`):**

```
plugins/meinchat/meinchat/services/event_bus.py:12:1
  F401 'typing.Iterable' imported but unused
plugins/meinchat/meinchat/services/stream_token.py:9:1
  F401 'uuid.UUID' imported but unused
plugins/meinchat/populate_db.py:41:5
  F841 local variable 'result' is assigned to but never used
plugins/meinchat/tests/unit/services/test_attachment_service.py:3:1
  F401 'unittest.mock.MagicMock' imported but unused
plugins/meinchat/tests/unit/services/test_message_service.py:2:1
  F401 'unittest.mock.ANY' imported but unused
plugins/meinchat/tests/unit/services/test_rate_limiter.py:2:1
  F401 'time' imported but unused
```

Per `feedback_no_noqa_without_permission.md` these must be **fixed
at the root** (delete the unused imports / unused variable), not
suppressed with `# noqa`.

---

## 3. Code-quality observations (the `meinchat/` part that exists)

Spot-read of `nickname_service.py`, `token_transfer_service.py`, and
the 609-line `routes.py`:

### 3.1 What's solid

- **Liskov + DI-clean services.** Every service takes its repo
  through the constructor; `_test_db_url()` not even needed because
  unit tests `MagicMock` the repo. Pattern matches `MEMORY.md`'s
  service template.
- **Typed exceptions everywhere.** `NicknameTakenError`,
  `NicknameBannedError`, `NicknameNotFoundError`,
  `ContactSelfAddError`, `MessageBodyTooLongError`,
  `InsufficientTokensError`, `SelfTransferError`,
  `RateLimitExceeded` — no magic-string error checks.
- **Route error mapping is consistent.** Every write route follows
  `try / except TypedError → rollback + jsonify with status`. Zero
  silent failures.
- **Rate limiter cached on `current_app`** so it's a single instance
  per process, correct for Redis counter semantics.
- **SSE Redis fanout** — `redis_event_bus.py` exists alongside
  in-process `event_bus.py`, with auto-selection at runtime. This
  exceeds plan §302 which deferred multi-worker support.
- **Banned-nickname grace-period reclaim** is implemented as a
  lazy check on `PUT /nickname/me` (correct: cron-only would create
  a window where the slug is unreclaimable for up to 24 h).
- **Snapshot of `sender_nickname`** at message-send time
  (`message.sender_nickname`) — implements sprint plan's "later
  rename doesn't break old threads" promise.

### 3.2 Concerns

1. **`routes.py` is 609 lines flat** instead of the planned per-
   subsystem split (`routes/{nickname,contacts,messaging,token_transfer}.py`).
   Functional but degrades navigability; one-off auth changes
   require touching all 17 routes in one file.
2. **`_enforce_rate` returns Response-or-None** as a control-flow
   pattern. Caller must remember `if blocked is not None: return
   blocked`. A decorator (`@rate_limit("send", per_min=30)`) would
   be tighter.
3. **`_meinchat_config()` reads `current_app.config_store` per call**
   — every route re-reads the entire plugin config dict. Cheap at
   current volumes; flag if N×routes×requests scales.
4. **`NicknameService.ban` / `.unban` exist as dead code** until
   the admin routes ship.
5. **No concurrency test** for the token-transfer row lock. Sprint
   plan §82 specifically called for one (two threads against the
   same sender balance, exactly one succeeds). Unit tests cover the
   *exception types* but not the *lock semantics*.
6. **`events.py` not present** — plan §122 wanted a typed events
   module. Events are fired with string topics (`f"user:{user_id}"`),
   so a typo at the publisher silently breaks fan-out.

---

## 4. Definition-of-done gate (sprint §556–567)

Going through the sprint's own gate, item by item:

| DoD item | Status |
|---|---|
| (1) ≥ 40 pytest cases, all green | ✅ **111** cases, **111** passing |
| (2) `pre-commit-check.sh --full` green on every touched repo | ❌ **Fails on flake8** (6 unused imports / 1 unused local) |
| (3a) No `# noqa` / `# type: ignore` added without approval | ✅ I see none in `meinchat/` |
| (3b) No host-side `npm install` in bind-mounted `vbwd-fe-core` | n/a — no fe work yet |
| (3c) No raw SQL migrations | ✅ four well-formed Alembic ops |
| (3d) All plugin code in own repo | ❌ none of 3 repos exist |
| (3e) No temp branches | ✅ no temp branches because nothing pushed |
| (4) No deprecated code left behind | ⚠️ empty `alembic/` dir orphan; ban/unban service code unreachable |
| (5) Demo instance smoke-test alice ↔ bob loop | ❌ fe-user does not exist |

**3 PASS, 5 FAIL, 1 partial. Not done.**

---

## 5. Risk matrix

| Risk | Severity | Why |
|---|---|---|
| **No fe-user → feature invisible** | 🔴 Blocking | The whole feature was for end-users. Backend in isolation has zero user value. |
| **Pre-commit fails (lint)** | 🔴 Blocking-for-CI | Sprint DoD §2 requires green; plugin can't be tagged `1.0.0` until fixed. ~30-min fix. |
| **No standalone repos** | 🔴 Policy violation | `feedback_plugins_always_in_own_repos.md` is hard rule. |
| **Admin routes absent** | 🟠 Scope gap | Three declared `admin_permissions` are unenforceable. Operators cannot ban abusive nicknames in prod. |
| **No concurrent-transfer test** | 🟠 Quality gap | Sprint §82 explicitly called for it. Race condition risk in production. |
| **Empty `alembic/` orphan dir** | 🟡 Cleanup | Misleading; might cause future devs to put migrations in the wrong place. |
| **No Prometheus metrics** | 🟡 Operability | 4 metrics promised; 0 implemented. Production will be silent. |
| **No integration / route tests** | 🟡 Quality gap | Migrations + auth + rate limit + SSE round-trip are unverified end-to-end. |
| **Version 0.1.0 vs spec 1.0.0** | 🟡 Drift | Plugin metadata says 0.1; sprint promises 1.0. Cosmetic until publish. |
| **Sprint doc not moved to `done/`** | 🟢 Bookkeeping | Reflects reality — it isn't done. |

---

## 6. What's been added since the 04-24 review

For accountability, what changed in the 5 days between this review
and `01-meinchat-review.md`:

| 04-24 review said | 04-29 reality |
|---|---|
| ❌ `token_transfer.py` model missing | ✅ Added (46 LoC) |
| ❌ `token_transfer_repository.py` missing | ✅ Added (31 LoC) |
| ❌ `token_transfer_service.py` missing | ✅ Added (127 LoC) |
| ❌ `/api/v1/token-transfer/*` routes missing | ✅ Added (POST + GET history) |
| ❌ `populate_db.py` missing | ✅ Added |
| ❌ All 4 Alembic migrations missing | ✅ Added at correct location, registered in `alembic.ini` |
| ❌ `tests/unit/repositories/` empty | ❌ Still empty |
| ❌ `tests/unit/routes/` empty | ❌ Still empty |
| ❌ `tests/integration/` empty | ❌ Still empty |
| ❌ Admin routes missing | ❌ Still missing |
| ❌ fe-user plugin missing | ❌ Still missing |
| ❌ fe-admin plugin missing | ❌ Still missing |
| ❌ No standalone repos | ❌ Still none |
| ❌ Tests: 100 → expected to grow | ✅ 111 (added 11, all token-transfer service specs) |

**Backend correctness gap closed substantially. Frontend gap
unchanged. Repo / CI gap unchanged.**

Also noteworthy: a new MEMORY.md feedback file was added today
(`feedback_plugin_migrations_in_plugin.md`) clarifying that
migrations live at `plugins/<name>/migrations/versions/` not core —
the meinchat migrations comply with this new rule even though it
landed today, which suggests they were placed correctly first try.

---

## 7. Remaining work to sprint completion

In rough TDD-friendly order:

### 7a. Backend completeness (~1 day)

1. **Fix the 6 lint failures** (delete unused imports / unused
   variable). 30 min. Fast.
2. **Delete the orphan `alembic/` directory.** 1 min.
3. **Add admin routes** for ban / unban / conversation-inspect /
   transfer-audit (4 routes; service-layer logic already exists).
   ~3 h including tests.
4. **Bump plugin version to `1.0.0`** in metadata.
5. **Concurrent-transfer integration test** — pytest with two
   `threading.Thread`s against the same sender balance. ~1 h.
6. **Repository unit tests** — at minimum
   `nickname_repository.search_prefix` correctness against
   `text_pattern_ops` index. ~2 h.
7. **Route unit tests** via Flask test client — 401/403/404/429
   paths for the most-used 6 routes. ~3 h.
8. **Integration tests** — register → set-nickname → add-contact →
   start-conversation → send-message → read → delete, against real
   DB fixture. ~2 h.
9. **Prometheus metrics** — 4 counters/gauges per sprint plan §535-
   539. Wire `prometheus_client.Counter` / `Gauge` instances into
   service methods. ~2 h.

### 7b. Repo extraction (~0.5 day)

10. `git filter-repo` extract `vbwd-backend/plugins/meinchat/` →
    standalone `vbwd-plugin-meinchat`.
11. `gh repo create VBWD-platform/vbwd-plugin-meinchat --public
    --source ... --remote origin --push`.
12. CI workflow from `vbwd-plugin-stripe`'s `.github/workflows/tests.yml`
    template, swap `stripe` → `meinchat`.
13. Add to `recipes/push-plugins.sh` + EXPECTED list in
    `recipes/ci-status.sh`.

### 7c. fe-user plugin (~3 days)

14. Scaffold `vbwd-fe-user-plugin-meinchat/` with named-export
    `meinchatPlugin` per `MEMORY.md` convention.
15. **Stores** (TDD-first): `useNicknameStore`, `useContactsStore`,
    `useMeinchatStore` (conversations + messages). Vitest specs.
16. **Composables**: `useMessagingStream` (EventSource +
    auto-reconnect), `useNicknameSearch` (debounced), `useImageAttach`.
17. **Views**: `InboxView`, `ContactsView`, `ConversationView`,
    `NicknameSettingsView`.
18. **Components**: `ConversationHeader`, `MessageBubble` (text /
    image / system-token-transfer variants), `MessageComposer`,
    `InboxRow`, `ContactRow`, `AddContactDialog`, `FindUserDialog`,
    `TokenTransferDialog`, `NicknameAvailabilityIndicator`,
    `SafeLinkify`.
19. **userNavRegistry** wiring for `💬 Messages` sidebar entry
    with unread badge.
20. **i18n** for 8 locales (en first; the other 7 machine-translated
    with `// TODO: human-review` markers).
21. **Playwright E2E** — alice ↔ bob loop matching sprint DoD §5.

### 7d. fe-admin plugin (~1 day)

22. Three views: conversations inspector, nicknames table with
    ban/unban, transfers audit log.

### 7e. Demo enable + smoke (~0.5 day)

23. Add `meinchat` to the `main` instance's
    `backend-plugins.json`, `fe-user-plugins.json`,
    `fe-admin-plugins.json`. Re-deploy. Smoke-test live.

24. **Move sprint doc to `done/`. Write completion report.**

**Total to true sprint close: ~6 person-days** (close to the
original sprint estimate of 8 days minus the 2 days the backend
already represents).

---

## 8. Recommendation

**Proceed in this order, no skips:**

1. **Hour 0–1** — fix the 6 lint failures and delete the orphan
   `alembic/` dir. Pre-commit gate green. *Required for any further
   commit per the engineering contract.*
2. **Hour 1–4** — admin routes (4 endpoints; service code exists).
   Closes the unenforceable-permissions gap.
3. **Day 1 second half** — concurrent-transfer test + repository +
   route tests + Prometheus metrics. Backend at production quality.
4. **Day 2** — extract to standalone `vbwd-plugin-meinchat` repo,
   create on GitHub, push, wire CI.
5. **Days 3–5** — write `vbwd-fe-user-plugin-meinchat` (this is the
   bulk of the remaining work and is the only thing that makes the
   feature visible).
6. **Day 6** — `vbwd-fe-admin-plugin-meinchat`, demo enable on
   `vbwd.cc`, smoke alice ↔ bob, move sprint to `done/`, write
   completion report.

**Anti-pattern to avoid:** shipping fe-user before fixing the lint
gate or the missing admin routes. The pre-commit failure means the
backend cannot legitimately be tagged `1.0.0`, and the fe-user
plugin would be calling routes (admin moderation) that don't exist
— users could be flooded by abusive nicknames with no operator
remediation path.

---

## 9. Files touched by this review (read-only)

```
vbwd-backend/plugins/meinchat/__init__.py                   2485 B
vbwd-backend/plugins/meinchat/meinchat/routes.py             609 lines
vbwd-backend/plugins/meinchat/meinchat/models/*.py           5 files
vbwd-backend/plugins/meinchat/meinchat/services/*.py        11 files, 1707 LoC
vbwd-backend/plugins/meinchat/meinchat/repositories/*.py     5 files
vbwd-backend/plugins/meinchat/migrations/versions/*.py       4 files
vbwd-backend/plugins/meinchat/tests/unit/services/*.py      11 files, 88 test funcs
vbwd-backend/plugins/meinchat/populate_db.py                  ✅
vbwd-backend/alembic.ini                                    line 36 — meinchat path registered
docs/dev_log/20260424/sprints/57-meinchat.md                609 lines (the plan)
docs/dev_log/20260424/reports/01-meinchat-review.md         555 lines (prior review)
```

No code modified by this review.
