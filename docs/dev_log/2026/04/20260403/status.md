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
| 20 | [CI Pipeline Fixes](sprints/20-ci-fixes.md) | Planned | — |

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

## Market Research

| Report | Path |
|--------|------|
| Payment Plugins ASEAN + JP + KR | [payment-plugins-asean.md](../../dev_docs/market-research/payment-plugins-asean.md) |
| Payment Plugins EU | [payment-plugins-eu.md](../../dev_docs/market-research/payment-plugins-eu.md) |
| Payment Plugins LATAM | [payment-plugins-latam.md](../../dev_docs/market-research/payment-plugins-latam.md) |
| Travel Integrations | [travel-integrations.md](../../dev_docs/market-research/travel-integrations.md) |
| Check-In Plugin HoReCa | [checkin-plugin-horeca.md](../../dev_docs/market-research/checkin-plugin-horeca.md) |

## Pre-Commit Status (2026-04-12)

All 3 modules pass `pre-commit-check.sh --full`:

| Module | Static Analysis | Unit Tests | Integration Tests | Result |
|--------|----------------|------------|-------------------|--------|
| **Backend** | Black + Flake8 + Mypy | 1409 passed, 5 skipped | 179 passed, 150 skipped | **PASS** |
| **fe-admin** | ESLint + TypeScript | 428 unit + 93 integration | — | **PASS** |
| **fe-user** | ESLint + TypeScript | 340 passed, 1 skipped | — | **PASS** |

## CI Status (2026-04-12)

22 repos failing on GitHub Actions — all due to Sprint 14-19 code not yet pushed to standalone repos. See [Sprint 20: CI Fixes](sprints/20-ci-fixes.md) for detailed analysis and deployment plan.

| Status | Count | Repos |
|--------|-------|-------|
| **Passing** | 13 | fe-core, fe-user-plugin-cms, fe-user-plugin-chat, fe-user-plugin-checkout, fe-user-plugin-ghrm, fe-user-plugin-stripe, fe-user-plugin-taro, fe-admin-plugin-cms, fe-admin-plugin-ghrm, fe-admin-plugin-taro, plugin-chat, plugin-mailchimp, vbwd-sdk |
| **Failing** | 22 | All others — awaiting code push |

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
- Page editor: "Page Widgets" section — choose widget per slot, saves with main Save button
- `CmsLayoutRenderer` merges page + layout widgets (page overrides for same area)
- Import/export support for `page_widget_assignments`
- Populate script: `_set_page_widgets()` helper, demo "About Us" testimonials widget
- 9 E2E tests (4 page-defined + 5 page-widget-slots with access level filtering)

### Bug Fixes

- **Taro session UUID error** — `UUID(UUID_object)` in `check_token_balance()` fixed with `isinstance` check
- **Alembic migration conflicts** — all incremental migrations now use `IF NOT EXISTS` / `_table_exists` guards
- **Legacy ADMIN permission fallback** — ADMIN users with no RBAC roles get all permissions

### Pre-Existing Test Fixes

- 31 backend unit test failures fixed (mock `_get_access_levels` binding, ADMIN fallback)
- 160 integration test skips reduced to 2 (API_BASE_URL, token field names, response shapes)
- 49 fe-admin Vitest failures fixed (auth store configuration in all test files)
- 7 tax test collisions fixed (unique codes per test)
- Taro/Booking/CMS DB connection exhaustion fixed (session-scoped app, engine dispose)
- Black formatting on 10 backend files
- Mypy: `Column[UUID]` → `UUID` cast
- TypeScript: `CmsPage.vue` pageWidgetAssignments type
