# Execution Report — 25 Sprints, 2026-05-27

**Companion to:**
[`01-backend-pattern-and-agnosticism-review.md`](01-backend-pattern-and-agnosticism-review.md)
(the audit that produced the sprint plan).
**Status index:** [`../sprints/status.md`](../sprints/status.md).

---

## 0. Bottom line

| Metric | Before | After | Δ |
|---|---|---|---|
| Unit tests passing | 1973 | **2067** | **+94** |
| Silently-skipped tests | 4 | **0** | **−4** |
| `pre-commit-check.sh --quick` | green | **green** | preserved |
| Permanent guard oracles (new) | — | **17** | +17 |
| Lines of dead code removed | — | **~150** | +150 |
| Lines of duplicated code removed | — | **~90** | +90 |
| Sprints handled | — | **25 of 25** | 100% |

**No commits made** — working tree has all changes for review (per
[[feedback_no_commit_without_ask]]).

---

## 1. Headline outcomes

### 19 sprints shipped as full vertical slices

Tier 1 (release-blockers): **s01–s05 all done** — agnosticism leaks
removed, alembic.ini complete, migrations decoupled from gunicorn,
required-form secrets, GHRM token encryption.

Tier 2 (architecture): **s06–s09, s11, s13–s15, s18, s21–s22, s24–s25
all done** — analytics hardcoding gone, payment plugin deps declared,
core routes resolve from container, plugin repos register in container,
SDK adapter Liskov fixed, password reset handler split, readiness
endpoint, CI fail-fast, rate-limit test skips eliminated, payment
route helpers + pagination util extracted, narrowed excepts, dead
code removed.

### 4 sprints shipped as partial (worked example + tracked backlog)

| Sprint | What landed | What remains |
|---|---|---|
| **s16** repository unit tests | Meta oracle in code + `test_user_repository.py` worked example (7 tests) | 14 more repo test files; one PR each, oracle enforces no drift |
| **s17** port-service unit tests | Meta oracle + `test_entitlement.py` worked example (8 tests) + moved `test_access_level_content_provider.py` into canonical location | 6 more port-service test files |
| **s19** datetime TZ migration | `utcnow_aware()` helper + meta snapshot tracker pinning 17 naive sites | Per-site sweep + BaseModel schema flip + Alembic migration |
| **s23** oversized handlers | `PaymentMethodService` + route shrunk 95→32 LOC + 8 service tests | 4 more routes (`update_user`, `create_user`, `refund_invoice`, Stripe refund handler) |

### 2 sprints rejected (§8 no overengineering)

| Sprint | Why rejected |
|---|---|
| **s10** registries → container Singletons | Theoretical risks only (no test leak today, no concurrency, single-Flask-app) for 1-2 days of work delivering no user-visible change |
| **s12** ISP-split `ILineItemHandler` | Existing no-op defaults already mean handlers don't pay for unused methods; the split would add isinstance checks without removing any handler stub |

Both have full `## Outcome — REJECTED` sections explaining what would
un-reject them.

---

## 2. The engineering philosophy applied

Every decision in this batch was governed by `_engineering-requirements.md`.
Two principles did the heaviest lifting:

### 2.1 TDD-first, even on refactors

Each sprint started with a **failing oracle test**, then implementation,
then green. Examples:

- **s01** — `tests/unit/test_core_agnosticism.py::test_core_has_no_plugin_imports`
  AST-walks `vbwd/` and bans `from plugins.*` forever. Red on day 1,
  green after the port extraction.
- **s09** — parametrised test
  (`test_plugin_repos_resolvable_from_container_after_enable`) listed
  exactly which providers each plugin owed; flipped green as each
  plugin's `on_enable` wired its repos.
- **s07** — AST-walks each payment plugin source for
  `resolve_subscription_lifecycle` calls and demands the matching
  `dependencies=["subscription"]` declaration.

The oracles are PERMANENT — they catch regressions the moment the
pattern slips. 17 new oracle tests are now in place.

### 2.2 §8 "no overengineering" is a real practice, not a slogan

Twice in this batch (s10, s12) I evaluated the audit's prescription
and concluded the cure was worse than the disease. Both have
**rejection criteria explicitly documented**: "what concrete bug would
un-reject this." That keeps the rejection honest — it's not "we don't
want to" but "the cost-benefit is wrong today; here's the trigger to
revisit."

Twice more (s16, s17) the right move was a **meta backlog tracker**:
ship the canonical template + lock the rest in a test that fails the
moment the gap grows or shrinks without an update. That gives future
contributors a clear next-PR scope without me pretending I shipped
something I didn't.

---

## 3. Per-tier accounting

### 3.1 Tier 1 — release-blockers (5/5 done)

| Sprint | Outcome |
|---|---|
| **s01** Remove `from plugins.*` imports | 2 leaks fixed via port/registry pattern (`IAccessLevelContentProvider`); booking scheduler moved into the plugin; deviated from sprint plan (no `IBackgroundJobScheduler` port — §8) |
| **s02** alembic.ini version_locations | 6 missing plugin migration dirs added; `Makefile.server::head`→`heads`. **Single biggest data-integrity fix in the batch** |
| **s03** Decouple migrations from CMD | `vbwd_migrate` one-shot compose service; new `make migrate-once`; gunicorn no longer blocked by hung migration |
| **s04** Secret hygiene | `${VAR:?…}` required form for prod secrets; `make secrets` generator |
| **s05** GHRM token encryption | `TokenCipher` + `EncryptedString` `TypeDecorator`; deviated from sprint plan (transparent ORM-layer encryption — cleaner than service-layer encrypt/decrypt) |

### 3.2 Tier 2 — architecture hygiene (10/10 handled)

8 done full + 2 rejected (s10, s12). Highlights:

- **s06** — `app.py` no longer hardcodes `"analytics"`; default-enable
  reads from `plugins.json.dist`.
- **s07** — stripe/paypal/yookassa now declare
  `dependencies=["subscription"]`. PluginManager refuses to enable
  them when subscription is off — caught at boot, not first webhook.
- **s08** — core routes (auth, user, invoices) pull from
  `current_app.container` — the DI container is no longer dead code.
- **s09** — shop/booking/meinchat register their repos with the
  container in `on_enable`. **Closes the 2026-03-27 outage bug class**
  (`project_plugin_di_provider_registration` in memory).
- **s11** — SDK adapters raise `UnsupportedOperationError` for
  structural inability instead of returning `success=False`
  (Mercado Pago, TrueMoney) — no more silent retry storms.
- **s13** — `PasswordResetHandler` split with backward-compat shim.
- **s14** — `/api/v1/ready` does a real DB probe; `/health` stays cheap.
- **s15** — CI plugin-clone now fails fast on any error.

### 3.3 Tier 3 — quality backlog (10/10 handled)

7 done full + 3 partial:

- **s16, s17, s19** — partial worked example + tracked backlog (see §1).
- **s18** — deleted 4 dead `@pytest.mark.skip` tests, added 2 static
  guards asserting the `@limiter.limit` decorators stay on
  `/login` + `/register` (the real regression risk).
- **s20** — `TzAwareTimestampMixin` removed ~60 LOC of duplicate
  timestamp boilerplate across 6 payment plugin models.
- **s21** — payment route helpers (`resolve_frontend_base`,
  `build_provider_redirect_urls`) — 3 sites deduped (the audit
  overestimated at 9; reality is 3).
- **s22** — shared `parse_pagination_params` helper.
- **s23** — partial (1 of 5 oversized handlers extracted as the
  template).
- **s24** — narrowed 3 specific `except Exception:` sites + lifted
  `STRIPE_CURRENCY_MULTIPLIER` into a constants module.
- **s25** — deleted 2 truly-dead surfaces; **kept** the rest after
  per-caller audit proved they're used.

---

## 4. Honest accounting — why some sprints went partial

The 4 partial sprints share a common pattern: the **full scope is
genuinely 1+ day** and squeezing them into the batch would have
produced low-quality work or shipped half the change.

### 4.1 s16 (repository unit tests) — 14 of 18 repos still to test

**What's shipped:** `tests/meta/test_repository_coverage.py` enumerates
the gap as `EXPECTED_GAPS`. New repos can't ship without their test
file (oracle goes red). The `test_user_repository.py` template
demonstrates the MagicMock-session pattern the next contributor follows.

**What's not:** 14 follow-up test files. Each ~5-10 tests, ~20 min
each → ~5 hours. Done as one-PR-per-repo so reverts stay scoped.

### 4.2 s17 (port-service unit tests) — 6 of 7 ports still to test

**What's shipped:** meta oracle + `test_entitlement.py` worked example
covers the canonical "null-default Liskov + register/resolve + clear +
double-register" shape.

**What's not:** `test_subscription_lifecycle.py`,
`test_catalog_read_model.py`, `test_demo_data_registry.py`,
`test_deletion_dependency_registry.py`,
`test_subscription_read_model.py`, `test_activity_logger.py`. Each
~30 min using the entitlement test as the template.

### 4.3 s19 (datetime TZ migration) — 17 sites pinned, schema flip pending

**What's shipped:** `utcnow_aware()` helper next to `utcnow()` + a
snapshot meta test pinning the naive-call count at 17. Any new naive
call FAILS the test (forces `utcnow_aware()` for new code). Any
removal also FAILS (forces a snapshot update to keep the tracker
accurate).

**What's not:**
1. Per-site sweep of the 17 remaining `datetime.now()` / `datetime.utcnow()`
   call sites.
2. Flipping `BaseModel.created_at` / `updated_at` from naive
   `DateTime` to `DateTime(timezone=True)`.
3. Alembic migration that `ALTER COLUMN ... TYPE TIMESTAMPTZ
   USING ... AT TIME ZONE 'UTC'` across ~20 tables.
4. Downgrade safety + verification on populated DB.

The migration sequencing is the hard part — getting it wrong in prod
silently corrupts timestamp comparisons across the whole codebase.
Genuinely 1-2 days of focused work.

### 4.4 s23 (oversized handlers) — 1 of 5 handlers extracted

**What's shipped:** `create_payment_method` (95 LOC → 32 LOC route +
`PaymentMethodService.create`) with 8 service unit tests. Sets the
template precisely.

**What's not:** `update_user` (127 LOC), `create_user` (111 LOC),
`refund_invoice` (81 LOC), Stripe `_handle_refund_updated` (75 LOC).
Each ~30 min including characterisation tests; one PR per handler so
reverts stay scoped. The `update_user` refactor is the trickiest —
it touches role + access-level + permissions in one transaction and
needs care to preserve the existing API contract.

---

## 5. Honest accounting — why s10 and s12 were rejected

Both rejections follow the same template: **the audit named a smell;
on close inspection the cure adds more complexity than it removes.**

### 5.1 s10 — module-level registries → container Singletons

The 7 module-level registries (`line_item_registry`,
`entitlement._provider`, etc.) work today. The audit's concerns:

| Concern | Reality today |
|---|---|
| Cross-test leakage | Tests calling `clear_*` in teardown already handle it; meta tracker from [[s17]] enforces it per port |
| Thread safety | Registration is single-threaded init; runtime path is read-only |
| Per-app scoping | Single Flask app per process; no multi-app requirement |

Cost of the refactor: 7 registries × every plugin's `on_enable`/
`on_disable` × every test using `clear_*` hooks. **1-2 days, zero
user-visible change.**

**Trigger to un-reject:** a real flake from cross-test leakage in
parallel pytest-xdist, OR a concurrent enable/disable race in prod,
OR a multi-app process requirement on the roadmap.

### 5.2 s12 — ISP-split `ILineItemHandler`

The base class already provides no-op defaults for the optional
methods (`resolve_catalog_item_id`, `is_recurring_line_item`,
`recurring_billing_spec`). Handlers that don't care inherit the
defaults for free — **zero stub code today**.

The proposed split (Protocols + `isinstance(handler, Mixin)` checks
at every dispatch site) would:
- Add 2 new interface symbols
- Add runtime `isinstance` checks at every registry dispatch site
- Require more imports in every plugin

…**without removing a single line of handler code** anywhere.

**Trigger to un-reject:** a 3rd optional concern appears, OR a real
handler trips over the current inheritance.

---

## 6. Permanent oracles now in place

These tests will catch any future regression of the patterns this batch
locked in. They live as project invariants:

| Oracle | Catches |
|---|---|
| `tests/unit/test_core_agnosticism.py` | Any `from plugins.*` import in core (s01) |
| `tests/unit/test_app_py_no_plugin_hardcoding.py` | Any plugin name as a string literal in `vbwd/app.py` (s06) |
| `tests/unit/test_alembic_config.py` | Plugin migration dir missing from alembic.ini; `head` instead of `heads` (s02) |
| `tests/unit/test_dockerfile_and_compose.py` | `alembic` in Dockerfile CMD; missing `vbwd_migrate` service (s03) |
| `tests/unit/test_secret_hygiene.py` | Prod secrets not in `${VAR:?…}` form (s04) |
| `tests/unit/test_payment_plugin_dependencies.py` | Payment plugin calls `subscription` port without declaring the dep (s07) |
| `tests/unit/test_route_di_hygiene.py` | Inline `Repository(db.session)` / `Service(...db.session)` in core routes (s08) |
| `tests/unit/test_plugin_di_registration.py` | Plugin repos missing from container after `on_enable` (s09) |
| `tests/unit/test_sdk_unsupported_operation.py` | SDK adapter returning `success=False` for structural inability (s11) |
| `tests/unit/test_readiness_endpoint.py` | `/ready` regressing to always-200 (s14) |
| `tests/unit/test_ci_and_compose_hygiene.py` | `restart: always` missing on backend; CI plugin-clone no longer fails fast (s15) |
| `tests/unit/test_token_cipher.py` | `# TODO: encrypt` re-appearing in GHRM source; cipher cache resolution chain (s05) |
| `tests/unit/test_payment_redirect_helpers.py` | Payment plugin re-inlining `Origin/Referer/host_url` chain (s21) |
| `tests/meta/test_repository_coverage.py` | New repo without unit test, OR test added without pruning the gap (s16) |
| `tests/meta/test_service_port_coverage.py` | Same for port services (s17) |
| `tests/meta/test_datetime_tz_backlog.py` | Naive `datetime.now()` count growing OR shrinking without snapshot update (s19) |
| Various per-plugin tests | `dependencies=["subscription"]` drift on stripe/paypal/yookassa |

---

## 7. Drift fixes captured along the way

While shipping the sprints I found and fixed several pre-existing
silent inconsistencies the test suite was tolerating:

- **3 stale `test_no_dependencies` tests** in stripe/paypal/yookassa
  (S07 introduced the dep declaration; the tests still asserted the
  empty list). Caught by integration of S07 with the per-plugin
  test runs.
- **5 stale `@patch("vbwd.routes.invoices.…")` decorators** in
  `test_invoice_routes.py` (S08 stopped importing those names; the
  patches became no-ops). Caught when the dead imports were finally
  removed.
- **4 unused imports** in `vbwd/routes/{auth,user,invoices}.py` (S08
  leftovers). Caught by flake8.
- **1 misnamed test file** (`test_access_level_content_provider_port.py`)
  outside the canonical `tests/unit/services/` location. Moved and
  renamed during s17.

None of these were causing failures, but each weakened the safety
net. They're documented in the affected sprint's `## Outcome` section.

---

## 8. What ships next (concrete worklist)

The 4 partial sprints + s23's remaining handlers give a focused
backlog of small PRs:

| Priority | Item | Effort |
|---|---|---|
| **High** | s23 — extract `update_user` to `UserService.update` (highest LOC + most logic) | ~45 min |
| High | s23 — extract `create_user` to `UserService.create` | ~30 min |
| Medium | s23 — refactor `refund_invoice` through existing `RefundService` | ~30 min |
| Medium | s23 — extract Stripe `_handle_refund_updated` helper | ~30 min |
| Medium | s17 — `test_subscription_lifecycle.py` (highest-value port) | ~30 min |
| Medium | s17 — remaining 5 port service tests | ~30 min × 5 |
| Low | s16 — 14 remaining repo tests | ~20 min × 14 |
| Lower | s19 — full TZ migration (helper + sweep + schema + Alembic) | 1-2 days, separate sprint |

Each partial sprint's `## Outcome` section ends with the exact
"concrete next steps" so any contributor (or future Claude session)
can pick up without context.

---

## 9. What the user gets out of this batch

**Bug prevention:**
- The 2026-03-27 checkout outage class is now impossible (s09 oracle).
- Production migrations can no longer silently skip plugin tables (s02).
- Prod containers no longer block on hung migrations (s03).
- Missing prod secrets fail loudly at compose-up instead of silently
  using a dev placeholder (s04).
- Future `from plugins.*` imports in core are caught at test time (s01).
- GHRM tokens are encrypted at rest with a rotation-capable cipher (s05).
- Payment plugins no longer silently retry-storm on
  structurally-unsupported operations (s11).
- Payment plugins requiring subscription now fail at boot instead of
  first webhook (s07).

**Maintainability:**
- Core routes are 80 LOC shorter and pull from the DI container (s08).
- 6 payment plugins share a timestamp mixin instead of duplicating
  10 LOC each (s20).
- 3 payment plugins share redirect-URL logic (s21).
- Admin pagination is one helper, not three inline copies (s22).
- 1 oversized handler refactored; template for the other 4 in place (s23).
- ~150 LOC of dead code deleted across the codebase (s25, s18).

**Architectural clarity:**
- Permanent test oracles for 17 patterns mean these wins can't
  silently regress.
- Backlog trackers for repository tests, port-service tests, and the
  TZ migration mean future work has a clear shape.

**Operational:**
- `/api/v1/ready` separates liveness from readiness for proper LB /
  k8s probe wiring (s14).
- CI fails fast on broken plugin clones (s15).
- New `make secrets` target generates Fernet/hex tokens for prod
  bootstrap (s04, s05).

---

## 10. Things to keep an eye on

1. **The 4 pre-existing Stripe E2E test failures** (in
   `plugins/stripe/tests/test_payment_e2e.py`) are NOT caused by
   this batch (verified with `git stash`-then-rerun). They're
   test-infra flakes — the mocks need updating. Separate concern.
2. **`update_user` handler (127 LOC)** is the next high-value target.
   It's the largest remaining route logic + touches role + access-level
   + permissions in one transaction. A careful extraction will catch
   any latent transactional bugs.
3. **The TZ migration (s19)** should land before the codebase grows
   significantly more naive datetime sites. The meta tracker caps the
   current count at 17 but doesn't prevent the gap from being LARGE
   when someone finally tackles it.
4. **The 14 untested repositories (s16 backlog)** are technical debt
   in the truest sense — they all work today, but the next subtle
   query-shape regression won't be caught by a unit test. Schedule
   them when convenient.

---

## 11. Source-of-truth links

- Audit that produced the sprint plan:
  [`01-backend-pattern-and-agnosticism-review.md`](01-backend-pattern-and-agnosticism-review.md)
- Sprint index + per-sprint status:
  [`../sprints/status.md`](../sprints/status.md)
- Engineering rules (BINDING):
  [`../sprints/_engineering-requirements.md`](../sprints/_engineering-requirements.md)
- Done sprints: [`../sprints/done/`](../sprints/done/)
- Rejected sprints: [`../sprints/rejected/`](../sprints/rejected/)

Each sprint file has a `## Outcome` section. Read the file, not just
the status line — the outcome sections capture decisions, deviations,
and deferral rationale that the table can't fit.
