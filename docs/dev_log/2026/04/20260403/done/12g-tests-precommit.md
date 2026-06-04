# Sprint 12g — Tests + Pre-commit

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · DevOps-first
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Comprehensive tests for the access level system. All 3 repos pass `pre-commit-check.sh --full`.

---

## Steps

| # | What |
|---|------|
| 1 | Backend unit tests: PermissionService, @require_permission decorator, wildcard matching |
| 2 | Backend integration tests: access API routes (CRUD, export/import, user-role assignment) |
| 3 | Backend integration tests: permission enforcement on plugin routes |
| 4 | Fe-admin unit tests: usePermissions composable, sidebar filtering |
| 5 | Fe-admin unit tests: AccessLevels + AccessLevelForm components |
| 6 | Fe-admin integration tests: router guard permission checks |
| 7 | Playwright E2E: super-admin sees all, limited role sees only permitted |
| 8 | Playwright E2E: create custom role, assign to user, verify access |
| 9 | Playwright E2E: export/import roles |
| 10 | `pre-commit-check.sh --full` — backend |
| 11 | `pre-commit-check.sh --full` — fe-admin |
| 12 | `pre-commit-check.sh --full` — fe-user |

---

## Test Scenarios

### Permission Decorator
- Super-admin (`*`) passes any permission check
- Wildcard (`shop.*`) passes `shop.products.view`
- Exact match passes
- Missing permission returns 403
- Unauthenticated returns 401
- Multi-role: union of permissions checked

### Access API
- Create role with permissions
- Update role permissions
- Cannot delete system role
- Export/import round-trip preserves data
- Assign/revoke role for user
- Permission listing includes all plugin permissions

### Frontend
- Sidebar hides items when user lacks permission
- Route guard blocks navigation to denied pages
- 403 page renders correctly
- Permission matrix: check/uncheck updates role

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
