# Dev Log — 2026-03-18

## Reports

| # | Report | Status |
|---|--------|--------|
| 01 | [vbwd-platform Metapackage Architecture](reports/01-vbwd-platform-metapackage-architecture.md) | Done |
| 02 | [Phase 1: Backend as pip Package](reports/02-phase1-backend-pip-package.md) | Done |
| 03 | [Phase 2: Frontend App Factory](reports/03-phase2-frontend-app-factory.md) | Done |
| 04 | [Phase 3/3b/3c/4: Platform Scaffolding](reports/04-phase3-platform-scaffolding.md) | Done |
| 05 | [Metapackage Sprint Summary](reports/05-metapackage-sprint-summary.md) | Done |
| 06 | [fe-user E2E Test Report](reports/06-fe-user-e2e-test-report.md) | Blocked |
| 07 | [Plugin Imports Update: src. → vbwd.](reports/07-plugin-imports-update.md) | Done |

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 01 | [vbwd-platform Metapackage](sprints/done/01-vbwd-platform-metapackage.md) | Done | [05](reports/05-metapackage-sprint-summary.md) |

## Done

- Sprint 01: vbwd-platform metapackage (Phases 1-6 complete)
  - Backend: src/ → vbwd/, pyproject.toml, 735+506 tests pass
  - Frontend: createVbwdUserApp() + createVbwdAdminApp() factories, 346+231 tests pass
  - Platform: scaffolding, Makefile (30+ targets), pre-commit scripts, CI, install recipe
  - Email: all-events Mailpit integration test (15/15 pass)
- All 10 backend plugin repos updated: `from src.` → `from vbwd.` (92 files, 280 refs)

## Blocked

- fe-user E2E tests: 222 tests, all failed due to missing Playwright browsers + backend not running
  - Fix: `npx playwright install` + `make up` + `npm run dev`

## Branches

| Repo | Branch |
|------|--------|
| `vbwd-backend` | `feature/platform` |
| `vbwd-fe-user` | `feature/platform` |
| `vbwd-fe-admin` | `feature/platform` |
| `VBWD-platform/vbwd-platform` | `main` |
