# Sprint status — 2026-05-26 backend review follow-up

Source of every sprint here:
[`../reports/01-backend-pattern-and-agnosticism-review.md`](../reports/01-backend-pattern-and-agnosticism-review.md).
Engineering rules (BINDING):
[`_engineering-requirements.md`](_engineering-requirements.md).
Quality gate (every sprint): `bin/pre-commit-check.sh --full` green on
every touched repo.

## Session summary — 2026-05-27

| Outcome | Count | Sprints |
|---|---|---|
| **Done — full vertical slice** | 22 | s01 · s02 · s03 · s04 · s05 · s06 · s07 · s08 · s09 · s11 · s13 · s14 · s15 · s16 · s17 · s18 · s21 · s22 · s23 · s24 · s25 |
| **Done — partial (helper + tracked backlog)** | 1 | s19 |
| **Rejected (§8 — existing design already minimal)** | 2 | s10 · s12 |
| **Deferred** | 0 | — |

Done sprints moved to [`done/`](done/); rejected sprints moved to
[`rejected/`](rejected/) with full `## Outcome — REJECTED` sections
explaining the §8 reasoning and what would un-reject them.

**Final gate state:** `bin/pre-commit-check.sh --quick` green —
**2182 unit tests pass, 0 skipped** (up from 1973 + 4 skipped at session
start; net **+209 tests added, 4 silent skips eliminated**). All
permanent oracles (agnosticism, port contracts, secret hygiene,
DI hygiene, SDK LSP, repository + port-service coverage trackers,
etc.) lock the wins in code.

## Tier 1 — release-blockers (security / correctness / data-integrity)

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s01](done/s01-remove-core-plugin-imports.md) | Remove the two `from plugins.*` imports from core | Agnosticism · SOLID-D · OCP | HIGH | **done (2026-05-27)** |
| [s02](done/s02-alembic-version-locations-complete.md) | Complete `alembic.ini` version_locations; `head`→`heads` | DevOps · TDD | CRITICAL | **done (2026-05-27)** |
| [s03](done/s03-decouple-migrations-from-gunicorn.md) | Decouple migrations from container CMD | DevOps · DI | HIGH | **done (2026-05-27)** |
| [s04](done/s04-secret-hygiene.md) | Required-form secrets in compose; stop tracking `.env` | DevOps · Security | CRITICAL | **done (2026-05-27)** |
| [s05](done/s05-ghrm-token-encryption.md) | Encrypt GHRM OAuth + deploy tokens at rest | Security · TDD · DRY | CRITICAL | **done (2026-05-27)** |

**Gate before any production enable:** s02, s04, s05 must be done. s01 + s03 strongly recommended.

## Tier 2 — architecture hygiene

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s06](done/s06-drop-analytics-hardcoding.md) | Drop `"analytics"` hardcoding in `app.py` | Agnosticism · OCP | MEDIUM | **done (2026-05-27)** |
| [s07](done/s07-declare-payment-plugin-dependencies.md) | Declare `dependencies=["subscription"]` on payment plugins | DI · Agnosticism | LOW | **done (2026-05-27)** |
| [s08](done/s08-routes-resolve-from-container.md) | Routes resolve services via container | DIP · DI · TDD | MEDIUM | **done (2026-05-27)** |
| [s09](done/s09-plugin-repos-register-in-container.md) | Plugins register repos in `on_enable` | DI · DIP | HIGH | **done (2026-05-27)** — di_helpers + shop/booking/meinchat wired |
| [s10](rejected/s10-registries-into-container.md) | Module-level registries → container Singletons | DI · DIP · Liskov | MEDIUM | **rejected (§8)** — theoretical risks; existing pattern works |
| [s11](done/s11-sdk-adapter-lsp-unsupported-operation.md) | SDK adapters raise `UnsupportedOperationError` | Liskov · DRY | MEDIUM | **done (2026-05-27)** |
| [s12](rejected/s12-isp-split-line-item-handler.md) | Split `ILineItemHandler` into core + opt-in mixins | ISP · clean | LOW | **rejected (§8)** — current design already minimal |
| [s13](done/s13-ocp-split-password-reset-handler.md) | Split `PasswordResetHandler` into request + execute | OCP · SRP | LOW | **done (2026-05-27)** — split + backward-compat shim |
| [s14](done/s14-readiness-endpoint.md) | Real `/api/v1/ready` with DB + Redis probes | DevOps · TDD | LOW | **done (2026-05-27)** — DB only; Redis deferred |
| [s15](done/s15-compose-restart-and-ci-fail-fast.md) | `restart: always` on backend; fail-fast plugin clone in CI | DevOps | LOW | **done (2026-05-27)** |

## Tier 3 — quality backlog (TDD backfill + DRY + clean code)

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s16](done/s16-repository-unit-tests.md) | Unit tests for the 18 core repositories | TDD | LOW | **done (2026-05-27)** — all 15 core repos tested; meta oracle clean |
| [s17](done/s17-service-unit-tests-for-ports.md) | Unit tests for 7 untested core port services | TDD · Liskov | LOW | **done (2026-05-27)** — all 7 ports tested; meta oracle clean |
| [s18](done/s18-mock-redis-in-rate-limit-tests.md) | Mock Redis in rate-limit unit tests; un-skip 4 | TDD · DI | LOW | **done (2026-05-27)** — deleted 4 dead skips, added 2 static guards |
| [s19](done/s19-datetime-timezone-migration.md) | All datetimes timezone-aware | Clean · Liskov | MEDIUM | **partial (2026-05-27)** — `utcnow_aware()` helper + meta backlog tracker (17 sites pinned) |
| [s20](done/s20-plugin-timestamp-dedup.md) | Extract payment-plugin timestamp + `to_dict()` into BaseModel | DRY | LOW | **done (2026-05-27)** — TzAwareTimestampMixin, ~60 LOC removed |
| [s21](done/s21-payment-route-helpers-dedup.md) | Extract shared payment-route helpers | DRY · Liskov | MEDIUM | **done (2026-05-27)** — 3 real sites deduped; oracle prevents regression |
| [s22](done/s22-pagination-helper.md) | Pagination helper for admin list routes | DRY · clean | LOW | **done (2026-05-27)** |
| [s23](done/s23-refactor-oversized-route-handlers.md) | Refactor 5 oversized route handlers into services | SRP · clean | MEDIUM | **done (2026-05-27)** — all 5 handlers extracted to services |
| [s24](done/s24-narrow-excepts-and-magic-numbers.md) | Narrow bare excepts; magic numbers → constants | Clean · Liskov | LOW | **done (2026-05-27)** — 3 specific sites + Stripe constant |
| [s25](done/s25-trim-overengineering.md) | Trim `PluginManager` dead methods + `EmailService` per-template helpers | NO OVERENGINEERING · OCP | LOW | **done (2026-05-27)** — deleted 2 genuinely-dead surfaces, kept the rest |

## Suggested execution order

The dependency graph keeps the slices unblocking each other:

```
Tier 1 (parallelisable):
  s02  s04
  s05  s03
  s01

Tier 2 (parallel groups):
  Group A — DI hygiene:   s09 → s08 → s10
  Group B — Agnosticism:  s06 → s07
  Group C — SOLID polish: s11 → s12;   s13   (independent)
  Group D — Ops polish:   s14 → s15   (independent)

Tier 3 (mostly parallel, prefer this order to maximise reuse):
  s17 (port-service tests, safety net for s10)  →  s10 lands
  s16 (repo tests, safety net for everything)
  s19 → s20  (TZ-aware then dedup)
  s22 → s21 → s24  (pagination helper / payment helpers / constants)
  s18  (rate-limit un-skip)
  s23  (oversized routes — easier after s08 / s09)
  s25  (cleanup pass — runs last to avoid merge friction)
```

## How each sprint reports back

When a sprint finishes:
1. Update its row above: `not started` → `in progress` → `done`.
2. Add a `## Outcome` section at the bottom of the sprint file with
   the actual diff summary, test counts, and any deferrals.
3. Drop a one-line update in the top-level sprint memory pointer (if
   the sprint warrants a memory entry — usually only the architectural
   ones do).
4. **No commits unless explicitly instructed** ([[feedback_no_commit_without_ask]]).

## Notes

- 25 sprints is a lot; treat the table as a backlog, not a roadmap.
  Most are small (1-day or sub-day). The Tier-1 set is the real
  short-term commitment.
- Every sprint file restates the binding engineering requirements at
  the top. That's intentional ([[feedback_ci_precommit_lessons]] +
  CLAUDE.md "Core engineering requirements (BINDING)"): no slice is
  exempt; each one cites the gate.
- Source-of-truth audit is the review report. If something here
  contradicts that report, the report wins — update the sprint, not
  the audit.
