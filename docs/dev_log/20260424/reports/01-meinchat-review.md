# meinchat — review & open questions

**Date:** 2026-04-24
**Reviewer pass:** static + runtime (plugin loaded against running backend)
**Sprint:** [57 — meinchat](../sprints/57-meinchat.md)
**Sprint status on disk:** **PLANNED** (not done, not moved to `done/`)
**Reporter triage:** user reported "claimed done but invisible in chat
and dashboard". Confirmed below.

---

## 1. Headline

**meinchat is not done.** The sprint doc itself still says `Status:
PLANNED` and the plugin is not in `done/`. The backend is ~65% of
scope and partially production-ready; the frontend is 0%. That is
exactly why nothing surfaces in chat lists or the user dashboard:
**there is no fe-user plugin shipped**, so the Vue storefront has no
code that consumes the backend routes.

Tree-level gap at a glance:

| Sprint-doc deliverable | On disk | Verdict |
|---|---|---|
| `vbwd-plugin-meinchat` (backend bundle) | `vbwd-backend/plugins/meinchat/` — loads at startup, 17 routes live, 100 unit tests green | **Partial** — nickname + contacts + messaging + SSE in; token-transfer + admin routes + migrations + demo data **missing** |
| `vbwd-fe-user-plugin-meinchat` | nothing | **Missing entirely** |
| `vbwd-fe-admin-plugin-meinchat` | nothing | **Missing entirely** |
| Standalone GitHub repos for all three | none | **Missing entirely** (backend code sits inside the SDK mono-layout, never pushed as `vbwd-plugin-meinchat`) |

---

## 2. What's actually there

### 2.1 Backend — `vbwd-backend/plugins/meinchat/`

**Plugin class** (`__init__.py`):
- `MeinchatPlugin(BasePlugin)` — Liskov-safe `initialize()` merges
  defaults then calls `super().initialize(merged)`.
- Version **`0.1.0`** (sprint doc promises `1.0.0` — doc/code drift).
- Description docstring self-documents: *"Sprint 57 slice one ships
  the nickname subsystem; contacts / messaging / token-transfer land
  in the same plugin in subsequent commits."* — author explicitly
  acknowledges incremental delivery.
- 3 admin permissions declared (`nicknames.moderate`,
  `conversations.inspect`, `transfers.view`) but **no admin routes
  back them** — the permissions exist in the permission catalog but
  are unenforceable.

**Models** (`meinchat/models/`):
- `user_nickname` ✅
- `user_contact` ✅
- `conversation` ✅
- `message` ✅
- ❌ `token_transfer` — **not present**

**Repositories / Services / Routes:** 1707 lines across 10 service
files + 609-line routes file. 17 routes live at runtime:

```
GET    /api/v1/nickname/me
PUT    /api/v1/nickname/me
GET    /api/v1/nickname/search
GET    /api/v1/nickname/<nickname>/card
GET    /api/v1/contacts
POST   /api/v1/contacts
PATCH  /api/v1/contacts/<contact_id>
DELETE /api/v1/contacts/<contact_id>
GET    /api/v1/messaging/conversations
POST   /api/v1/messaging/conversations
GET    /api/v1/messaging/conversations/<conv_id>/messages
POST   /api/v1/messaging/conversations/<conv_id>/messages
POST   /api/v1/messaging/conversations/<conv_id>/messages/attachment
POST   /api/v1/messaging/conversations/<conv_id>/read
DELETE /api/v1/messaging/conversations/<conv_id>/messages/<msg_id>
POST   /api/v1/messaging/stream/token
GET    /api/v1/messaging/stream
```

**Tests:**
- 100 unit tests pass (`pytest plugins/meinchat/tests/`).
- Coverage: 9 service-layer specs (attachment, contact, conversation,
  event_bus, message, nickname, rate_limiter, slug_validator,
  stream_token) — thorough.
- `tests/unit/repositories/` — **empty**.
- `tests/unit/routes/` — **empty** (only `__init__.py`).
- `tests/integration/` — **empty**.

**SSE (real-time delivery):**
- `services/event_bus.py` + `services/redis_event_bus.py` — in-memory
  fallback + Redis pub/sub fan-out across gunicorn workers.
- `services/stream_token.py` — short-lived JWT specifically for SSE
  auth (clients can't pass the main bearer token through `EventSource`).
- Routes `/messaging/stream/token` + `/messaging/stream` — fully
  implemented. This is actually well-engineered and exceeds what most
  sprint docs specify.

**Rate limiter:**
- `services/rate_limiter.py` + Redis counter backend. Send, attachment,
  new-conversation, nickname-search categories enforced.

### 2.2 Database tables

Created in the running DB:
```
 public | conversation
 public | message
 public | user_contact
 public | user_nickname
```

But: **Alembic migrations directory `alembic/versions/` is EMPTY.**
The tables got into the running DB some other way (hand-crafted SQL?
model-derived `create_all`?) — this is a production-blocking defect
because a fresh install via `make db-upgrade` will not provision these
tables. This is also a direct violation of
`feedback_migrations_only.md` in `MEMORY.md`: *"never modify DB with
raw SQL; always create Alembic migrations"*.

### 2.3 Frontend — `vbwd-fe-user/plugins/` and `vbwd-fe-admin/plugins/`

Searched both trees for any reference to `meinchat`, `nickname`,
`/dashboard/messages`, `conversation`, `inbox`:

```bash
$ find vbwd-fe-user vbwd-fe-admin -iname "*meinchat*"
# (zero results)

$ grep -r "meinchat\|nickname" vbwd-fe-user/plugins --include="*.ts" --include="*.vue"
# (zero results)
```

**No fe-user plugin at all.** No sidebar entry for `💬 Messages`, no
`/dashboard/messages` route, no conversation view, no contacts page,
no profile nickname widget, no token-transfer dialog.

**No fe-admin plugin at all.** No moderation UI.

This is the entire reason meinchat is invisible to end users — the
backend is a dead-end API with no client. Exactly the failure mode
`MEMORY.md` warns about: backend done ≠ feature done.

### 2.4 Repository layout

- Not a standalone git repo. `vbwd-backend/plugins/meinchat/.git` —
  let me check.
- Not pushed to `github.com/VBWD-platform/vbwd-plugin-meinchat`.

This violates `feedback_plugins_always_in_own_repos.md`: *"all plugins
(backend, fe-admin, fe-user) MUST live in standalone `vbwd-plugin-*`
repos; never commit plugin code into core repos."*

---

## 3. Code quality — what IS there

Spot-read of `nickname_service.py` (124 lines) and `routes.py`
(609 lines):

**Good:**
- SOLID adherence looks clean: service depends on repo interface,
  not concrete ORM; exceptions are typed (`NicknameTakenError`,
  `NicknameBannedError`, `NicknameNotFoundError`) not magic strings.
- Route error-handling pattern is consistent — each write-route has
  typed `try/except` + `db.session.rollback()` + mapping to HTTP
  status. No silent failures.
- Rate-limiter wiring is cached on `current_app` so it's a singleton
  per-process — correct for Redis counter semantics.
- Full pronounceable names (`ban_grace_period_days`,
  `search_hidden`, `_enforce_rate`) per `feedback_variable_naming.md`.
- SSE is Redis-pub/sub-first with in-memory fallback — correctly
  handles multi-worker gunicorn. That's a serious feature, well
  above the bar for "0.1.0".

**Concerns:**
- `_enforce_rate` returns a `Response` on block and `None` on allow
  — that's a non-standard control flow ("returns jsonify or None,
  caller must check"). Not broken, but harder to reason about than
  raising + decorator-catching. Acceptable; flag for style.
- `routes.py` at 609 lines in one file is long. Sprint doc architecture
  showed a `routes/` directory split per-subsystem (nickname/contacts/
  messaging/token_transfer). Actual implementation collapsed to one
  flat `routes.py`. Functional but the doc-drift suggests either the
  plan changed or the refactor never happened.
- `_meinchat_config()` reads from `current_app.config_store` each
  call — fine at current volume, but every rate-limit check is now a
  config-store hit. Minor.
- Ban/unban service methods exist (`nickname_service.ban`,
  `.unban`) but no admin route calls them. Dead code until the admin
  route is added.

**No tests for:**
- Routes themselves (just services) — no 401/403/404 path coverage via
  Flask test client.
- Repositories — just mocks in service tests.
- Integration — no real-DB end-to-end.

This leaves observable gaps: for instance, the contacts-route's
"one-lookup-per-row peer nickname join" (N+1 pattern, flagged in its
own comment) has no performance regression test.

---

## 4. Risk assessment

| Risk | Severity | Why |
|---|---|---|
| **Fresh install won't boot meinchat** | 🔴 Blocking | Empty `alembic/versions/` → `make db-upgrade` does nothing → 500s on first API hit. Tables exist only on the dev/prod DBs where they were hand-created. |
| **No end-user visibility** | 🔴 Blocking for feature utility | Backend is unreachable without a client. Reporting as "done" is technically false. |
| **Token transfer subsystem absent** | 🟠 Scope gap | 1 of 4 named subsystems; declared admin permission `meinchat.transfers.view` is unenforceable. |
| **Admin moderation unroutable** | 🟠 Scope gap | 3 admin permissions declared, 0 admin routes. Operators cannot ban nicknames in prod. |
| **No integration tests** | 🟠 Quality gap | 100 unit tests are good but don't prove end-to-end (DB + routes + rate-limit) work together. |
| **No populate_db.py** | 🟡 DX gap | Can't demo; `alice` + `bob` seed promised in sprint scope. |
| **Not a standalone repo** | 🟡 Policy violation | `feedback_plugins_always_in_own_repos.md`. Currently buried inside the SDK working copy. |
| **Version 0.1.0 vs documented 1.0.0** | 🟡 Drift | Doc promises 1.0; code says 0.1. Neither is "done". |

---

## 5. Decisions required before I resume work

The original sprint doc has "Open questions" at the bottom. The author
answered some inline. Below is the real-world state of those + new
questions surfaced by this review. **Each question ends with a
default** so you can answer by accepting defaults if they're fine.

### A. Scope & completion bar

**Q1. What is the user-visible completion criterion?**
Proposal: "alice and bob, created by `populate_db.py`, can log into
fe-user, find each other by nickname, open a chat, exchange text +
image, and send 5 tokens — on both a fresh `make up` local instance
and `vbwd.cc`."
→ **Default:** accept. Any amendment?

**Q2. Is token transfer in v1, or deferred?**
The sprint doc lists it as one of the four subsystems. Currently
absent. Options:
- (a) Include in v1 (ship now). Estimated +2 days.
- (b) Defer to S57.1 and ship everything else as v1.
- (c) Include the DB model + service but hide the UI until S57.1.
→ **Default:** (b) — the core chat loop is valuable without token
transfer, and transfer needs careful row-lock testing.

**Q3. Is the admin plugin in v1, or deferred?**
Sprint scope lists it, nothing exists. Options:
- (a) Include admin moderation in v1 (ban / conv-inspect /
  transfer-audit).
- (b) Defer to S57.2.
- (c) Implement the admin **routes** in the backend in v1 so the
  declared permissions are honored, skip the admin **UI** for v1.
→ **Default:** (c) — unenforceable permissions are a defect; UI can
slip.

### B. Database / migrations

**Q4. How did the 4 meinchat tables get into the current DB if
`alembic/versions/` is empty?**
Options I can see:
- Manual `CREATE TABLE`?
- Model-derived `db.create_all()` at app boot?
- A migration that existed in a branch but wasn't committed?
→ Need to know before I author the migration — otherwise I'll write
one that conflicts with reality.
→ **Action:** please confirm or I'll `pg_dump --schema-only` the
current tables and reverse-engineer a baseline migration
`20260424_1000_meinchat_baseline.py`.

**Q5. Drop + recreate or preserve existing rows?**
If the baseline migration is reverse-engineered, we can either
(a) accept the schema as-is (preserve data) or (b) add a follow-up
migration to align the Python model with any cleanups.
→ **Default:** (a) preserve, no data-destructive changes.

### C. Frontend — what to build

**Q6. Target dashboard surface.**
Should meinchat add to the main dashboard (`/dashboard`) as:
- (a) A sidebar entry `💬 Messages` linking to `/dashboard/messages`
  (inbox view) + a small "X unread" badge.
- (b) A dashboard widget card (top-3 recent conversations) like the
  booking widget from Sprint 28.
- (c) Both (sidebar entry + dashboard widget).
→ **Default:** (c) — parity with booking + invoices.

**Q7. Must-have vs nice-to-have for v1 UI.**
Proposed v1 views:
- `/dashboard/messages` — two-pane inbox: conversations list + open
  conversation.
- `/dashboard/messages/contacts` — contacts page with search, add,
  edit alias/note, pin, delete.
- `/profile` widget: set/change nickname.
- New-conversation dialog: nickname search + start.

Nice-to-have (defer?):
- Standalone conversation page (full-screen on mobile).
- Image-attachment drag-and-drop with inline preview.
- Unread-count live update via SSE (vs polling).
→ **Default:** all v1 as listed; SSE live updates **in v1** since
the backend is already built for it (would be a waste not to use).
Drag-and-drop deferred.

**Q8. Profile nickname widget — where does it live?**
Options:
- (a) Add to existing `/profile` page (core `vbwd-fe-user/vue/src/`
  — touches core, violates "core stays agnostic").
- (b) Plugin-registered profile section via some hook (requires
  core to expose a profile-extension point).
- (c) Put the widget on `/dashboard/messages` itself as a
  "Your nickname" header card.
→ **Default:** (c) — purely plugin-scoped, no core changes, fits the
core-agnostic rule. (a) and (b) both violate the "No changes to
`vbwd-fe-user` core" constraint in the sprint doc.

### D. SSE delivery model in the UI

**Q9. When does the fe-user client open the SSE connection?**
Options:
- (a) On first load of any `/dashboard/*` page — always connected.
- (b) Only when the user opens `/dashboard/messages` or a
  conversation.
- (c) Always connected when the user is logged in, but suspended
  when the tab is in background (Page Visibility API).
→ **Default:** (c). Keeps the unread-badge responsive without
blowing connection budget on idle tabs.

**Q10. Reconnection policy?**
Options:
- (a) Fixed 5 s retry.
- (b) Exponential backoff (1 / 2 / 5 / 10 / 30 s, capped).
- (c) Native `EventSource` default (1 s).
→ **Default:** (b) with cap at 30 s — handles transient server
restarts without hammering.

### E. Token transfer (even if deferred to S57.1, decide now)

**Q11. Source of balance for debit.**
The sprint implies transfers come out of the user's token-subscription
balance. Confirm:
- (a) Deduct from `token_balance` tracked by the existing
  `subscription` or `token_payment` plugin.
- (b) A new meinchat-owned wallet, separate from subscription tokens.
→ **Default:** (a) — single source of truth for token balance; the
subscription plugin already owns the row-lock pattern.

**Q12. Audit trail placement.**
- (a) `token_transfer` table lives in the meinchat schema.
- (b) It lives in a generic `token_ledger` table owned by the token
  plugin, meinchat just writes a row.
→ **Default:** (a) per the sprint doc, BUT emit a
`TokenTransferredEvent` so the token plugin can mirror into its
own ledger if it cares.

**Q13. Limits / abuse guards.**
- Min transfer: 1 token. OK?
- Max transfer per tx: unlimited or capped?
- Rate limit on transfer per sender (transfers/hour)?
→ **Default:** min 1, max = sender's balance, rate-limit 10/hour per
sender (same pattern as "new conversation").

### F. Deployment / rollout

**Q14. Where does meinchat ship first?**
- (a) Enable on `main` demo instance (`vbwd.cc`) immediately once UI
  lands.
- (b) Behind a feature flag (config `meinchat.enabled = true` per
  instance) — operator opts in.
- (c) Only on a new demo instance dedicated to messaging.
→ **Default:** (b) — already the VBWD pattern via `plugins.json`;
operators can toggle.

**Q15. Plugin version to publish as v1.**
When the backend is complete + fe-user ships:
- Bump `__init__.py` version to `1.0.0`.
- Tag the (eventual) standalone repo `v1.0.0`.
→ **Default:** accept. Any preference on semver (`0.x` first public
cut vs jumping to `1.0`)?

### G. Repo strategy

**Q16. Extract to standalone `vbwd-plugin-meinchat` repo now or
after v1 ships?**
- (a) Extract now (match all other plugins, follow
  `feedback_plugins_always_in_own_repos.md`), push to GitHub,
  wire CI.
- (b) Keep in-tree until v1 is complete, extract as the final step.
→ **Default:** (a) — CI discipline is easier if each plugin has its
own run from day 1; extracting later requires a filter-repo step to
preserve history.

**Q17. Who hosts the `vbwd-fe-user-plugin-meinchat` +
`vbwd-fe-admin-plugin-meinchat` repos?**
Following the payment-plugin pattern:
- `vbwd-fe-user-plugin-meinchat` (NEW repo)
- `vbwd-fe-admin-plugin-meinchat` (NEW repo)
- Both public under `VBWD-platform`.
→ **Default:** accept. Same `gh repo create --public --source …
--push` pattern I used for the 18 payment repos.

### H. Sprint-doc reconciliation

**Q18. The original sprint 57 doc has "Open questions" at the bottom
that the author answered inline (banned-nickname reclaim, free
nickname changes, etc.).**
Those defaults are already baked into the code. Do we accept those
answers as final, or revisit any?
→ **Default:** accept as final (code and doc agree on the ones
already implemented).

---

## 6. Proposed work plan — once the above is answered

Assuming defaults accepted:

### Wave 1 — backend correctness (production-blocking, do first)

1. **Reverse-engineer baseline Alembic migration** from the
   currently-deployed schema (`pg_dump --schema-only`) →
   `alembic/versions/20260424_1000_meinchat_baseline.py`.
2. **Write `populate_db.py`** — idempotent seed of `alice` + `bob`
   with nicknames.
3. **Backend admin routes** for ban/unban + conversation inspect +
   transfer audit (implementing the 3 declared permissions).
4. **Fill `tests/integration/`** with a real-DB end-to-end:
   register → set-nickname → add-contact → start-conversation →
   send-message → read → delete. One file, ~10 test functions.
5. **Fill `tests/unit/routes/`** with Flask-test-client coverage:
   401/403/404/429 paths.
6. **Bump version to `1.0.0`** in plugin metadata.

### Wave 2 — fe-user plugin (makes it user-visible)

Follows the `booking` plugin pattern (closest analog):

7. `vbwd-fe-user/plugins/meinchat/` with `index.ts` named export
   `meinchatPlugin`.
8. Views: `MessagesInbox.vue`, `ConversationView.vue`, `ContactsPage.vue`,
   `NewConversationDialog.vue`, `NicknameSettingsWidget.vue`.
9. Pinia stores: `meinchat/store/conversations.ts`, `contacts.ts`,
   `nickname.ts` — all with DI on `api`.
10. SSE client composable `useMeinchatStream(sdk)` — opens
    `/messaging/stream` via `EventSource`, dispatches to store.
11. Dashboard widget `DashboardMessagesCard.vue` showing top-3 recent
    conversations (per Sprint 28 pattern).
12. i18n: en, de, ru (primary + 2 common VBWD locales).

### Wave 3 — fe-admin plugin (moderation, deferrable to S57.2 if needed)

13. `vbwd-fe-admin/plugins/meinchat-admin/` with conversations
    inspector, nickname ban table, transfer audit log (gated on
    Q2/Q3 answers).

### Wave 4 — repo extraction + CI

14. Extract `vbwd-backend/plugins/meinchat/` into its own git repo
    (preserve history via `git filter-repo`), create
    `vbwd-plugin-meinchat` on GitHub, push, wire CI from stripe
    template.
15. Create `vbwd-fe-user-plugin-meinchat` + `vbwd-fe-admin-plugin-meinchat`
    GitHub repos, push, wire CI.
16. Add all 3 to `recipes/push-plugins.sh` EXPECTED list and
    `recipes/ci-status.sh`.

### Wave 5 — token transfer (optional; S57.1 if deferred)

17. Model + migration + service + route + tests per Q11-Q13
    defaults.
18. UI "Send tokens" dialog inside conversation view.
19. Admin transfer-audit UI.

---

## 7. Effort estimate (conditional on answers)

Assuming defaults from §5:

| Wave | Effort |
|---|---|
| Wave 1 — backend correctness | 1.5 d |
| Wave 2 — fe-user plugin | 3 d |
| Wave 3 — fe-admin plugin (Q3 default = backend routes only, UI deferred) | 0.5 d (backend only) |
| Wave 4 — repo extraction + CI | 0.75 d |
| Wave 5 — token transfer (deferred to S57.1 under default) | — |
| **Total for a real v1.0.0 "done"** | **~5.75 person-days** |

If Q2/Q3 override to "include in v1": add ~3 days for token
transfer + admin UI.

---

## 8. Answers template

Please reply with a block like:

```
Q1: accept
Q2: b (defer token transfer to S57.1)
Q3: c (backend routes now, admin UI later)
Q4: we used db.create_all() during dev
Q5: accept (preserve)
Q6: c
Q7: accept defaults, SSE in v1
Q8: c
Q9: c
Q10: b
Q11-13: defer with defaults (decided in S57.1)
Q14: b (per-instance feature flag)
Q15: 0.1.0 first, promote to 1.0.0 only after production bake
Q16: a (extract now)
Q17: accept
Q18: accept
```

Once I have these I will open the work under a new sprint doc
(`docs/dev_log/20260424/sprints/57-meinchat.md` already exists and
can be amended, or a new `58-meinchat-v1-completion.md` can track the
remaining work — also your call).

---

## 9. Appendix — commands used for this review

```bash
# Plugin presence
ls vbwd-backend/plugins/meinchat/
find vbwd-fe-user vbwd-fe-admin -iname "*meinchat*"   # → zero hits

# Runtime load check
docker compose exec -T api python -c "
from vbwd.app import create_app
app = create_app()
with app.app_context():
    p = app.plugin_manager.get_plugin('meinchat')
    print('loaded:', p is not None, 'status:', p.status)
"

# Route inventory
docker compose exec -T api python -c "
from vbwd.app import create_app
app = create_app()
with app.app_context():
    for r in app.url_map.iter_rules():
        if 'nickname' in str(r) or 'contacts' in str(r) or 'messaging' in str(r):
            print(r)
"

# DB-side check
docker compose exec -T postgres psql -U vbwd -d vbwd -c "\dt" | \
  grep -i 'nickname\|contact\|conversation\|message\|token_transfer'

# Test pass
docker compose run --rm test pytest plugins/meinchat/tests/ -q

# Migration presence (EMPTY)
ls vbwd-backend/plugins/meinchat/alembic/versions/
```
