# meinchat — follow-up review

**Date:** 2026-04-29 (later session)
**Sprint:** [57 — meinchat](../sprints/57-meinchat.md)
**Predecessor reviews:**
- [01-meinchat-review.md](./01-meinchat-review.md) — 04-24, ~65% backend
- [02-meinchat-code-review.md](./02-meinchat-code-review.md) — 04-29 morning, ~85% backend, 0% frontend
- [03-meinchat-completion.md](./03-meinchat-completion.md) — 04-29 mid-day, claims IMPLEMENTED
**Methodology:** runtime test suite, file-tree diff vs sprint plan, vitest run on both
fe plugins, sprint-DoD gate re-evaluated.

---

## 1. Headline

The team made **substantial progress** since report 02. The gap from
**~85% backend / 0% frontend** to **fully running on localhost** was
closed in one work session.

**Sprint status:** the doc header now reads
`Status: IMPLEMENTED — 2026-04-29 (pending repo extraction + prod
deploy)`. That is the most accurate self-assessment so far — neither
"PLANNED" nor "DONE", but a real intermediate state.

**However, report 03 over-claims completion in two ways:**

1. **Cosmetic gaps closed by report 02 are still open** — three named
   plan items missing, fe-admin missing standard plugin files, no
   e2e tests, no Prometheus metrics.
2. **Demo enable is not where report 03 says it is** — report 03
   states the plugin is enabled in
   `vbwd-demo-instances/instances/local/{backend,fe-user,fe-admin}/plugins.json`
   but `vbwd-demo-instances/` does not exist in the repo. The plugin
   *is* enabled in the canonical fe-user / fe-admin
   `plugins/plugins.json` (visible in the diff just landed), so the
   *enablement* is real — but the report's path is inaccurate.

The 9-row Definition-of-Done gate in report 03 reads `8/9 PASS`.
Re-checking line by line, my count is **6/9 PASS, 2 partial, 1
soft-fail.** Detail in §4.

---

## 2. What was actually delivered since report 02

Verified independently. Counts come from running the suites.

### 2.1 Backend (gaps from report 02)

| Report 02 finding | Status now |
|---|---|
| Pre-commit FAILS (6 unused imports) | ✅ **`bin/pre-commit-check.sh --plugin meinchat --quick` returns "SUCCESS: All checks passed!"** |
| Admin routes absent (4 routes promised) | ✅ **5 admin routes live**: `GET /admin/meinchat/nicknames`, `POST /admin/meinchat/nicknames/<id>/ban`, `POST /admin/meinchat/nicknames/<id>/unban`, `GET /admin/meinchat/conversations/<id>`, `GET /admin/meinchat/transfers` |
| Plugin version 0.1.0 vs spec 1.0.0 | ✅ **`version="1.0.0"`** in `__init__.py` |
| Concurrent-transfer test (sprint §82) missing | ✅ `tests/integration/test_token_transfer_concurrent.py` (1 test) |
| Empty `tests/unit/repositories/` | ❌ **still empty** — `nickname_repository` SQL test went to `tests/integration/` instead, which is fine (it's a real-DB test) but the unit-level dir is still hollow |
| Empty `tests/unit/routes/` | ✅ Now has `test_admin_routes_auth.py` (4 tests) |
| Empty `tests/integration/` | ✅ Now has 2 files (`test_nickname_repository.py` 2 tests, `test_token_transfer_concurrent.py` 1 test) — **3 integration tests total** |
| Orphan `alembic/` dir | ✅ **deleted** |
| Test count 111 | ✅ **128 tests collected, 128 passing** (88 service + 4 admin auth + 3 integration + 33 misc) |
| Prometheus metrics — 4 promised, 0 implemented | ❌ **still 0** — `grep prometheus` plugin-wide returns zero hits |

### 2.2 fe-user plugin (was 0%, now real)

Tree at `vbwd-fe-user/plugins/meinchat/`:

```
README.md, config.json, admin-config.json, index.ts
locales/  en de es fr ja ru th zh    (8/8 ✅)
src/api.ts                            (typed wrapper ✅)
src/views/  InboxView ContactsView ConversationView NicknameSettingsView (4/4 ✅)
src/components/  AddContactDialog ContactRow ConversationHeader
                  FindUserDialog InboxRow MessageBubble MessageComposer
                  TokenTransferDialog                                     (8/9 ⚠)
src/composables/  useMessagingStream useNicknameSearch                    (2/3 ⚠)
src/stores/  useContactsStore useMeinchatStore useNicknameStore           (3/3 ✅)
tests/  meinchat-plugin.spec.ts + 4 unit specs                            (5 files, 23 tests ✅)
```

**Vitest:** `npx vitest run plugins/meinchat/` → **5 files / 23 tests
passing.**

**Code volume:** 1453 LoC across 4 views + 8 components.

**Sidebar wiring** (sprint §330): index.ts line 59 calls
`userNavRegistry.register({ to: '/dashboard/messages', labelKey:
'meinchat.nav.messages', testId: 'nav-messages' })`. ✅

### 2.3 fe-admin plugin (was 0%, now real)

Tree at `vbwd-fe-admin/plugins/meinchat-admin/`:

```
index.ts
locales/  8 locales                                (8/8 ✅)
src/api.ts                                          (✅)
src/views/  MeinchatConversationInspector
            MeinchatNicknamesList
            MeinchatTransfersList                  (3/3 ✅, sprint §494-497)
tests/  meinchat-admin-plugin.spec.ts              (1 file, 4 tests)
```

**Vitest:** `npx vitest run plugins/meinchat-admin/` → **1 file / 4
tests passing.**

**Code volume:** 445 LoC across 3 views.

**Routes registered:** `meinchat-admin-nicknames`,
`meinchat-admin-conversations` (list),
`meinchat-admin-conversation-detail` (per-conversation),
`meinchat-admin-transfers`. ✅

---

## 3. Gaps still open

### 3a. Plan items the team skipped (or report 03 didn't catch)

| Plan reference | Item | Severity |
|---|---|---|
| §374 | `NicknameAvailabilityIndicator.vue` — component for live nickname availability check during typing | 🟡 minor — backend `GET /nickname/<n>/card` already supports the check; UI just doesn't have the indicator |
| §378 | `useImageAttach.ts` — composable for client-side image preview + size pre-check before upload | 🟠 functional — without it, the `MessageComposer.vue` likely doesn't have client-side preview, and oversized images fly to the server only to be 413'd |
| §523 | `SafeLinkify.vue` — XSS-safe URL linkification | 🟠 security — bodies render via Vue `{{ }}` which escapes (so XSS-safe by default), but plain URLs in messages won't auto-link without this. Sprint plan calls it out as a posture item; current implementation falls back to plain text. |
| §387 | `tests/e2e/` — Playwright alice ↔ bob full-loop test (sprint DoD §5 explicitly cites this) | 🟠 quality — vitest covers stores + composable internals; no end-to-end browser test of the alice → @bob → image → tokens loop |
| §503-513 | `populate_db.py` enriched scenario (3 messages, 1 image, 1 read receipt, 1 transfer) | ✅ exists — already verified in report 02 |
| §517 §1 | Image MIME re-encode to **WebP**, EXIF stripped | ✅ verified in report 02 |
| §521 §2 | SSE token revocation list on logout | ❌ still no Redis revocation list — JWT just expires after TTL |
| §535-540 | 4 Prometheus metrics | ❌ none implemented |
| §544-553 | Standalone GitHub repos for backend + fe-user + fe-admin | ❌ **0 of 3 exist** |
| §564 | "All plugin code lives in own repo" (sprint DoD §3d) | ❌ violated |
| §567 | Smoke `vbwd.cc` | ❌ depends on repos + deploy pipeline |

### 3b. fe-admin plugin hygiene

`vbwd-fe-admin/plugins/meinchat-admin/` is missing:

- ❌ `config.json` — every other admin plugin has one (e.g. `subscription-admin/config.json`).
- ❌ `admin-config.json` — same.
- ❌ `README.md` — every standalone plugin has one.

These three missing files mean the plugin doesn't follow the project
convention and may render a blank "Plugin info" panel in the core
Settings → Plugins → Meinchat Admin page.

### 3c. fe-admin test coverage is thin

Only one spec file with 4 tests, all of which exercise the manifest
itself (route registration, locale registration). **Zero tests** on
the three views or the API client. The 4 manifest tests don't catch
SQL/auth/UI regressions on the moderation surfaces.

### 3d. Demo-instance enablement

Report 03 says the plugin is enabled in
`vbwd-demo-instances/instances/local/{backend,fe-user,fe-admin}/plugins.json`.

Reality:
- ❌ `vbwd-demo-instances/` does **not exist** as a directory in this
  working copy.
- ✅ `vbwd-fe-user/plugins/plugins.json` has `meinchat` enabled (just
  added this session — system reminder confirmed it).
- ✅ `vbwd-fe-admin/plugins/plugins.json` has `meinchat-admin`
  enabled (just added).
- ✅ `vbwd-backend/plugins/plugins.json` has `meinchat` enabled (per
  report 02).

So the plugin **is** enabled — just at the canonical `plugins/plugins.json`
in each app, not at the path report 03 cites. Functionally fine, but
the report's path is inaccurate.

### 3e. Sprint doc bookkeeping

- Sprint header line 3 says
  `**Status:** IMPLEMENTED — 2026-04-29 (pending repo extraction + prod deploy …)`
  ✅ accurate.
- Sprint doc still in `sprints/`, not in `done/`. ✅ Correct, given the
  pending operator actions.
- `done/` directory does not exist for 20260424. To be created when
  the sprint actually closes.

---

## 4. Definition-of-done gate — re-evaluated

Sprint plan §556–567 lists 9 DoD items. Report 03 read `8/9 PASS`.
My independent check:

| DoD line | Per spec | Status now | Notes |
|---|---|---|---|
| (1) ≥ 40 backend pytest cases, all green | "≥ 40" | ✅ **128 + 3 = 131 cases, all green** | Counted via `pytest --collect-only`. |
| (2) `pre-commit-check.sh --full` green on every touched repo | full pass | ⚠️ **Partial** — backend `--quick` PASSes; `--full` (which also runs `--integration`) was not re-verified this session. Front-end plugin pre-commit gates not run as part of this. |
| (3a) No `# noqa` / `# type: ignore` added without approval | none | ✅ |
| (3b) No host-side `npm install` in bind-mounted `vbwd-fe-core` | none | ✅ — fe-user + fe-admin both run via Docker dev-server. |
| (3c) No raw SQL migrations | none | ✅ — 4 well-formed Alembic ops at `plugins/meinchat/migrations/versions/`. |
| (3d) All plugin code in its own repo | 3 standalone repos | ❌ **0 of 3 exist** |
| (3e) No temp branches | none | ✅ — nothing pushed yet; trivially clean. |
| (4) No deprecated code left behind | clean | ✅ — orphan `alembic/` dir removed. |
| (5) Demo instance smoke alice ↔ bob loop on `vbwd.cc` | live | ❌ — depends on repos + deploy. Report 03 §4 verifies a localhost loop, which is a partial credit. |

**Score:** **6 PASS, 2 partial (#2 wasn't re-verified `--full`; #5
local-only), 1 outright FAIL (#3d).** Closer to "almost done" than
"done".

---

## 5. The work remaining

In TDD-friendly order, **~2 days of work** to get from "IMPLEMENTED"
to "DONE":

### 5a. Plan-item fill-ins (~3 hours)

1. **`useImageAttach.ts`** — client-side preview + ≤ 5 MB pre-check;
   reject early in `MessageComposer.vue` so we don't 413 the server.
   Vitest spec authored first.
2. **`SafeLinkify.vue`** — only emit `<a>` for parsed `URL` with
   `http:` / `https:` scheme. Vitest XSS round-trip test
   (`<script>alert(1)</script>` → escaped, `https://example.com` →
   `<a target="_blank" rel="noopener">`).
3. **`NicknameAvailabilityIndicator.vue`** — debounced 300 ms,
   green/red dot beside the input in `NicknameSettingsView`.

### 5b. fe-admin hygiene (~30 min)

4. Add `config.json`, `admin-config.json`, `README.md` to
   `vbwd-fe-admin/plugins/meinchat-admin/` matching the template
   used by `subscription-admin`.

### 5c. Test coverage gaps (~2 hours)

5. **fe-admin views** — vitest specs for each of the three views
   (mount + storeToRefs + table render + ban/unban click). At least
   3-5 specs each.
6. **Playwright e2e** — alice ↔ bob full loop. Sprint DoD §5
   literally requires this.

### 5d. Standalone-repo extraction (~1 hour)

7. `git filter-repo` extract each of the three plugin directories
   into its own repo. Push to:
   - `github.com/VBWD-platform/vbwd-plugin-meinchat`
   - `github.com/VBWD-platform/vbwd-fe-user-plugin-meinchat`
   - `github.com/VBWD-platform/vbwd-fe-admin-plugin-meinchat`
   Wire CI from the existing template (use stripe/booking as
   reference).
8. Add all 3 to `recipes/push-plugins.sh` EXPECTED list and to
   `recipes/ci-status.sh` so the monitor shows their CI health.

### 5e. Observability (~2 hours)

9. **4 Prometheus metrics** per sprint plan §535-540:
   - `meinchat_messages_sent_total{kind=text|attachment|system}`
   - `meinchat_sse_connections_gauge`
   - `meinchat_token_transfer_volume_total{direction=in|out}`
   - `meinchat_token_transfer_failures_total{reason=insufficient_balance|self|rate_limit}`
   Wire `prometheus_client` Counter / Gauge instances into the
   relevant service methods. Test that the `/metrics` endpoint
   surfaces them.

### 5f. SSE revocation (optional, ~1 hour)

10. Add a Redis SET `meinchat:stream-token-revoked:{user_id}` written
    on logout, checked at `/messaging/stream` connect time. Closes
    sprint §521 §2. Optional because the token TTL is 60 min, so a
    logged-out user can still receive their own SSE events for up to
    an hour — debatable whether that's a real risk.

### 5g. Move sprint to done (~5 min)

11. After (1)-(9): move
    `docs/dev_log/20260424/sprints/57-meinchat.md` →
    `docs/dev_log/20260424/done/57-meinchat.md`, write
    `docs/dev_log/20260424/reports/05-meinchat-final.md`.

---

## 6. Comparison: trajectory across reviews

| Concern | 04-24 (report 01) | 04-29 morning (report 02) | 04-29 evening (this) |
|---|---|---|---|
| Backend: token transfer | ❌ missing | ✅ added | ✅ |
| Backend: migrations | ❌ wrong path | ✅ correct path, registered | ✅ |
| Backend: pre-commit gate | ❌ never run | ❌ FAIL on 6 imports | ✅ SUCCESS |
| Backend: admin routes | ❌ missing | ❌ missing | ✅ 5 routes |
| Backend: integration tests | 0 | 0 | ✅ 3 |
| Backend: route auth tests | 0 | 0 | ✅ 4 |
| Backend: Prometheus metrics | 0 of 4 | 0 of 4 | ❌ 0 of 4 |
| Backend: orphan alembic dir | present | present | ✅ removed |
| Plugin version | 0.1.0 | 0.1.0 | ✅ 1.0.0 |
| fe-user plugin | ❌ 0% | ❌ 0% | ⚠️ ~92% (3 named items missing) |
| fe-admin plugin | ❌ 0% | ❌ 0% | ⚠️ ~80% (3 hygiene files + view tests missing) |
| Standalone repos | ❌ 0 of 3 | ❌ 0 of 3 | ❌ **still 0 of 3** |
| Sprint header status | PLANNED | PLANNED | IMPLEMENTED |
| In `done/` | no | no | no |

**One-line trajectory:** went from sketch to running-on-localhost in
five days. The remaining ~2 days are detail work + repo extraction +
observability.

---

## 7. Recommendation

Don't tag `1.0.0` yet. Three branches you can pick:

**Option A — Strict close.** Do all of §5a-§5g. Sprint moves to
`done/` cleanly, all 9 DoD items pass, all 3 repos exist on GitHub,
Prometheus surfaces metrics, e2e covers the alice ↔ bob loop. ~2
days.

**Option B — Pragmatic close.** Do §5a (3 missing components),
§5b (fe-admin hygiene), §5d (repo extraction), §5g (sprint move).
Skip §5c view tests, §5e Prometheus, §5f SSE revocation; track them
as `S57.1`. ~1 day.

**Option C — Ship as-is.** Keep `Status: IMPLEMENTED`, accept the
gap. Don't move to `done/`. Note in the sprint a clear list of
follow-up work. Production deploy on `vbwd.cc` happens once the
operator extracts the repos.

My recommendation: **Option B**. The three missing components
(`SafeLinkify`, `useImageAttach`, `NicknameAvailabilityIndicator`)
are explicitly named in the plan; skipping them is doc-vs-code
drift that future devs will have to reconcile. Repo extraction is a
one-shot operation. The Prometheus + view-tests + SSE-revocation
work is genuinely follow-up scope and can move to S57.1 without
guilt.

---

## 8. Files referenced (read-only)

```
vbwd-backend/plugins/meinchat/                       (full tree)
vbwd-fe-user/plugins/meinchat/                       (full tree, 1453 LoC)
vbwd-fe-admin/plugins/meinchat-admin/                (full tree, 445 LoC)
vbwd-fe-user/plugins/plugins.json                    (line 117 — meinchat enabled)
vbwd-fe-admin/plugins/plugins.json                   (line 93 — meinchat-admin enabled)
docs/dev_log/20260424/sprints/57-meinchat.md         (the plan, 609 lines)
docs/dev_log/20260424/reports/01-meinchat-review.md  (prior, 555 lines)
docs/dev_log/20260424/reports/02-meinchat-code-review.md (prior, 671 lines)
docs/dev_log/20260424/reports/03-meinchat-completion.md  (prior, 173 lines)
```

No code modified by this review.
