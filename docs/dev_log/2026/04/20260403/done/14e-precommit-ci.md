# Sprint 14e — Pre-commit + CI

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DRY · Clean Code · DevOps-first
**Parent:** [14 — Access Control Bulletproof Tests](14-access-bulletproof-tests.md)

---

## Goal

All access control tests pass in pre-commit checks across all 3 repos. CI pipeline runs access tests on every PR.

---

## Steps

| # | What |
|---|------|
| 1 | Run `pre-commit-check.sh --full` in vbwd-backend — fix any failures |
| 2 | Run `pre-commit-check.sh --full` in vbwd-fe-admin — fix any failures |
| 3 | Run `pre-commit-check.sh --full` in vbwd-fe-user — fix any failures |
| 4 | Run Playwright E2E in fe-admin with `E2E_BASE_URL=http://localhost:8081` |
| 5 | Run Playwright E2E in fe-user with `E2E_BASE_URL=http://localhost:8080` |
| 6 | Verify all access-related tests pass in CI (GitHub Actions) |
| 7 | Update status.md with final test counts |

---

## Expected Test Counts

| Repo | Unit | Integration | E2E | Total |
|------|------|-------------|-----|-------|
| **backend** | ~680+ | ~30+ | — | ~710+ |
| **fe-admin** | ~330+ | ~90+ | ~20+ | ~440+ |
| **fe-user** | ~340+ | — | ~17+ | ~357+ |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
