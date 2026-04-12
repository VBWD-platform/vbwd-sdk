# Dev Log — 2026-04-03

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 12 | [Admin Access Levels — Overview](sprints/12-admin-access-levels.md) | Done | [Report](reports/01-sprint-12-14-access-control.md) |
| 13 | [Permission Matrix Table UI](done/13-permission-matrix-table.md) | Done | — |
| 14 | [Access Control Bulletproof Tests](sprints/14-access-bulletproof-tests.md) | Done | [Report](reports/01-sprint-12-14-access-control.md) |
| 15 | [Shipping & Discount Admin](sprints/15-shipping-discount-admin.md) | Done | [Report](reports/03-sprint-15-shipping-discount-tax.md) |
| 16 | [Pay with Token Balance](sprints/16-token-payment.md) | Planned | — |
| 17 | [User Access Levels (fe-user)](sprints/17-user-access-levels.md) | Done | [Report](reports/09-sprint-17-final.md) |
| 18 | [Access-Level-Driven Visibility](sprints/18-access-level-visibility.md) | Done | [Report](reports/11-sprint-18-final.md) |
| 19 | [Page-Defined Widgets](sprints/19-page-defined-widgets.md) | Done | [Report](reports/12-sprint-19-page-defined-widgets.md) |

## Reports

| # | Report | Date |
|---|--------|------|
| 01 | [Sprint 12-14: Access Control](reports/01-sprint-12-14-access-control.md) | 2026-04-04 |
| 02 | [Lessons Learned: Sprints 12-14](reports/02-lessons-learned.md) | 2026-04-04 |
| 03 | [Sprint 15: Shipping, Discount, Tax](reports/03-sprint-15-shipping-discount-tax.md) | 2026-04-04 |
| 04 | [Access Level Management System](reports/04-access-level-management.md) | 2026-04-06 |
| 05 | [Access Level Security Hardening](reports/05-access-level-security-hardening.md) | 2026-04-06 |
| 06 | [Sprint 17b: Subscription Access Levels](reports/06-sprint-17b-subscription-access-levels.md) | 2026-04-06 |
| 07 | [Sprint 17: Complete](reports/07-sprint-17-complete.md) | 2026-04-07 |
| 08 | [Lessons Learned: Sprint 17](reports/08-sprint-17-lessons-learned.md) | 2026-04-07 |
| 09 | [Sprint 17: Final Status](reports/09-sprint-17-final.md) | 2026-04-08 |
| 10 | [Sprint 18: Access-Level Visibility](reports/10-sprint-18-access-level-visibility.md) | 2026-04-08 |
| 11 | [Sprint 18: Final](reports/11-sprint-18-final.md) | 2026-04-12 |
| 12 | [Sprint 19: Page-Defined Widgets](reports/12-sprint-19-page-defined-widgets.md) | 2026-04-12 |

## Test Status (2026-04-12)

| Module | Tests | Result |
|--------|-------|--------|
| Backend unit | 1409 passed, 5 skipped | PASS |
| Backend integration (live API) | 327 passed, 2 skipped | PASS |
| fe-admin ESLint | 0 errors | PASS |
| fe-admin TypeScript | 0 errors | PASS |
| fe-admin Vitest | 428 passed | PASS |
| fe-user Vitest | 427 passed, 1 skipped | PASS |
| fe-admin Playwright E2E | 37 passed | PASS |

## Completed Since 2026-04-06

### Sprint 17 — User Access Levels (COMPLETE)

Full user-facing permission system across backend, admin panel, and user-facing app:
- `UserAccessLevel` model with plan auto-assignment via subscription events
- `@require_user_permission` decorator for user route protection
- Admin UI: two tabs (Admin / User access levels), extensible form fields
- fe-user: router guard, sidebar filtering, permission-gated dashboard cards
- 22 backend unit tests + 24 admin E2E tests

### Sprint 18 — Access-Level-Driven Content Visibility (COMPLETE)

Server-side content filtering based on user access levels:
- `required_access_level_ids` on `CmsLayoutWidget` and `CmsPage`
- CMS layout editor: "Visible to" per-widget multi-select
- CMS page editor: "Page visible to" restriction
- Dashboard cards gated by `hasUserPermission()`
- Anonymous = implicit "new" access level
- 4 E2E tests proving widget filtering + page 403

### Sprint 19 — Page-Defined Widgets (COMPLETE)

New `page-widget` area type for per-page widget selection:
- `CmsPageWidget` model + migration + API
- Layout editor: `page-widget` area type in dropdown
- Page editor: "Page Widgets" section — choose widget per slot
- Saves with main Save button (no separate save)
- Import/export support for `page_widget_assignments`
- Demo: "About Us" page gets testimonials widget
- 9 E2E tests (4 page-defined + 5 page-widget-slots with access levels)

### Pre-Existing Test Fixes

- 31 backend unit test failures fixed (mock `_get_access_levels` binding, ADMIN fallback)
- 160 integration test skips reduced to 2 (API_BASE_URL, token field names, response shapes)
- 49 fe-admin Vitest failures fixed (auth store configuration in all test files)
- 7 tax test collisions fixed (unique codes)
- 3 taro connection exhaustion errors fixed (session-scoped app fixture)
- All incremental migrations made idempotent (IF NOT EXISTS guards)
