# Sprint status — 2026-05-26 backend review follow-up

Source of every sprint here:
[`../reports/01-backend-pattern-and-agnosticism-review.md`](../reports/01-backend-pattern-and-agnosticism-review.md).
Engineering rules (BINDING):
[`_engineering-requirements.md`](_engineering-requirements.md).
Quality gate (every sprint): `bin/pre-commit-check.sh --full` green on
every touched repo.

## Tier 1 — release-blockers (security / correctness / data-integrity)

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s01](s01-remove-core-plugin-imports.md) | Remove the two `from plugins.*` imports from core | Agnosticism · SOLID-D · OCP | HIGH | not started |
| [s02](s02-alembic-version-locations-complete.md) | Complete `alembic.ini` version_locations; `head`→`heads` | DevOps · TDD | CRITICAL | not started |
| [s03](s03-decouple-migrations-from-gunicorn.md) | Decouple migrations from container CMD | DevOps · DI | HIGH | not started |
| [s04](s04-secret-hygiene.md) | Required-form secrets in compose; stop tracking `.env` | DevOps · Security | CRITICAL | not started |
| [s05](s05-ghrm-token-encryption.md) | Encrypt GHRM OAuth + deploy tokens at rest | Security · TDD · DRY | CRITICAL | not started |

**Gate before any production enable:** s02, s04, s05 must be done. s01 + s03 strongly recommended.

## Tier 2 — architecture hygiene

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s06](s06-drop-analytics-hardcoding.md) | Drop `"analytics"` hardcoding in `app.py` | Agnosticism · OCP | MEDIUM | not started |
| [s07](s07-declare-payment-plugin-dependencies.md) | Declare `dependencies=["subscription"]` on payment plugins | DI · Agnosticism | LOW | not started |
| [s08](s08-routes-resolve-from-container.md) | Routes resolve services via container | DIP · DI · TDD | MEDIUM | not started |
| [s09](s09-plugin-repos-register-in-container.md) | Plugins register repos in `on_enable` | DI · DIP | HIGH | not started |
| [s10](s10-registries-into-container.md) | Module-level registries → container Singletons | DI · DIP · Liskov | MEDIUM | not started |
| [s11](s11-sdk-adapter-lsp-unsupported-operation.md) | SDK adapters raise `UnsupportedOperationError` | Liskov · DRY | MEDIUM | not started |
| [s12](s12-isp-split-line-item-handler.md) | Split `ILineItemHandler` into core + opt-in mixins | ISP · clean | LOW | not started |
| [s13](s13-ocp-split-password-reset-handler.md) | Split `PasswordResetHandler` into request + execute | OCP · SRP | LOW | not started |
| [s14](s14-readiness-endpoint.md) | Real `/api/v1/ready` with DB + Redis probes | DevOps · TDD | LOW | not started |
| [s15](s15-compose-restart-and-ci-fail-fast.md) | `restart: always` on backend; fail-fast plugin clone in CI | DevOps | LOW | not started |

## Tier 3 — quality backlog (TDD backfill + DRY + clean code)

| Sprint | Title | Pillar | Risk | Status |
|---|---|---|---|---|
| [s16](s16-repository-unit-tests.md) | Unit tests for the 18 core repositories | TDD | LOW | not started |
| [s17](s17-service-unit-tests-for-ports.md) | Unit tests for 7 untested core port services | TDD · Liskov | LOW | not started |
| [s18](s18-mock-redis-in-rate-limit-tests.md) | Mock Redis in rate-limit unit tests; un-skip 4 | TDD · DI | LOW | not started |
| [s19](s19-datetime-timezone-migration.md) | All datetimes timezone-aware | Clean · Liskov | MEDIUM | not started |
| [s20](s20-plugin-timestamp-dedup.md) | Extract payment-plugin timestamp + `to_dict()` into BaseModel | DRY | LOW | not started |
| [s21](s21-payment-route-helpers-dedup.md) | Extract shared payment-route helpers | DRY · Liskov | MEDIUM | not started |
| [s22](s22-pagination-helper.md) | Pagination helper for admin list routes | DRY · clean | LOW | not started |
| [s23](s23-refactor-oversized-route-handlers.md) | Refactor 5 oversized route handlers into services | SRP · clean | MEDIUM | not started |
| [s24](s24-narrow-excepts-and-magic-numbers.md) | Narrow bare excepts; magic numbers → constants | Clean · Liskov | LOW | not started |
| [s25](s25-trim-overengineering.md) | Trim `PluginManager` dead methods + `EmailService` per-template helpers | NO OVERENGINEERING · OCP | LOW | not started |

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
