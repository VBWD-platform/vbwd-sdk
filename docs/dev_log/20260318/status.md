# Dev Log — 2026-03-18 / 2026-03-19

## Reports

| # | Report | Status |
|---|--------|--------|
| 01 | [vbwd-platform Metapackage Architecture](reports/01-vbwd-platform-metapackage-architecture.md) | Done |
| 02 | [Phase 1: Backend as pip Package](reports/02-phase1-backend-pip-package.md) | Done |
| 03 | [Phase 2: Frontend App Factory](reports/03-phase2-frontend-app-factory.md) | Done |
| 04 | [Phase 3/3b/3c/4: Platform Scaffolding](reports/04-phase3-platform-scaffolding.md) | Done |
| 05 | [Metapackage Sprint Summary](reports/05-metapackage-sprint-summary.md) | Done |
| 06 | [fe-user E2E Test Report](reports/06-fe-user-e2e-test-report.md) | Done |
| 07 | [Plugin Imports Update: src. → vbwd.](reports/07-plugin-imports-update.md) | Done |
| 08 | [All Green CI — Lessons Learned](reports/08-all-green-ci-lessons-learned.md) | Done |
| 09 | [Booking for Transport Aggregator](reports/09-booking-plugin-transport-aggregator-analysis.md) | Research |
| 10 | [Booking Sprint 02a/b/c Report](reports/10-booking-sprint-02abc-report.md) | Done |

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 01 | [vbwd-platform Metapackage](sprints/done/01-vbwd-platform-metapackage.md) | Done | [05](reports/05-metapackage-sprint-summary.md) |
| 02 | [Booking Plugin Bundle — Overview](sprints/02-booking-overview.md) | In Progress | [10](reports/10-booking-sprint-02abc-report.md) |
| 02a | [Booking Backend Plugin](sprints/done/02a-booking-be.md) | Done | [10](reports/10-booking-sprint-02abc-report.md) |
| 02b | [Booking Admin Frontend](sprints/done/02b-booking-fe-admin.md) | Done | [10](reports/10-booking-sprint-02abc-report.md) |
| 02c | [Booking User Frontend](sprints/done/02c-booking-fe-user.md) | Done | [10](reports/10-booking-sprint-02abc-report.md) |
| 02d | [Payment Authorize/Capture](sprints/done/02d-payment-authorize-capture.md) | Done | — |
| 02e | [Booking Import/Export + Event Export](sprints/02e-booking-import-export.md) | Planned | — |

## Done (2026-03-19)

- Sprint 02a: Backend plugin — 3 models, 3 repos, 3 services, 16 routes, 7 events, migration, populate_db.py (54 tests)
- Sprint 02b: Admin frontend — 2 stores, 5 views, extension registry nav (14 tests)
- Sprint 02c: User frontend — 1 store, 2 views, CMS widget registration (9 tests)
- Core: CUSTOM LineItemType + extra_data JSON column (9 tests)
- CI: --plugin flag, plugin-tests.yml with integration, platform CI split into 3 groups
- CI: 9 fixes for mypy, eslint, vitest, bash syntax, test skipping, repo visibility
- Total: 86 tests across 4 modules, all green

## Next

Sprint 02d done:
- Core: InvoiceStatus.AUTHORIZED + PaymentProviderPlugin.capture_payment/release_authorization
- Stripe: refactored to stripe/stripe/, Payment Intents with capture_method=manual
- PayPal: refactored to paypal/paypal/, intent=AUTHORIZE, void_authorization
- YooKassa: refactored to yookassa/yookassa/, capture flag configurable, release_authorization
- All 3 payment plugins: tests pass, lint green
- Booking plugins: config.json + admin-config.json added

Next: Sprint 02e (Import/Export) or continue with booking integration tests.
