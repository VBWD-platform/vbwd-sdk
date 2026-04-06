# Sprint Status — 2026-03-14

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 01 | Code Quality — vbwd-backend | ✅ Done | `reports/02-backend-quality-sprint-report.md` |
| 02 | Code Quality — vbwd-fe-admin | ✅ Done | `reports/03-fe-admin-quality-sprint-report.md` |
| 03 | Code Quality — vbwd-fe-user | ✅ Done | `reports/04-fe-user-quality-sprint-report.md` |
| 04 | Billing Gaps — recurring billing & subscription lifecycle | ✅ Done | `reports/07-billing-gaps-sprint-report.md` |
| 05 | Email System — templates, SMTP, Mailchimp demo, Mailpit | ✅ Done | `reports/08-email-system-sprint-report.md` |
| 06 | Fix "Get Package" button — wrong ID, no context, anonymous redirect | ✅ Done | `reports/09-fix-get-package-button-report.md` |
| 07 | GHRM Breadcrumb Widgets — CMS-style widgets, 3-tab admin config (General/CSS/Preview) | ⏳ Pending approval | `sprints/07-ghrm-breadcrumb-widgets.md` |
| 09 | Plugin Event Bus — unified EventBus, domain→bus bridge, EventContextRegistry, fix broken email events | ⏳ Pending approval | `sprints/09-plugin-event-bus.md` |
| 08 | CMS Routing Rules — default page, language/IP/country routing, nginx hybrid, admin UI | ⏳ Pending approval | `sprints/08-cms-routing-rules.md` |
| 10 | VBWD Org — GitHub org creation, repo transfers, plugin docs, public plugin repos | ⏳ Pending approval | `sprints/10-vbwd-org-and-plugin-repos.md` |
| 11 | Tarif Plan Detail Page — subscription row click, plan detail view, GHRM Software + GitHub Access tabs | ✅ Done | `reports/11-tarif-plan-detail-page-report.md` |
| — | GHRM Plugin v1 — production fix, partial sync, preview, markdown, plugin manager bug | ✅ Done | `reports/06-ghrm-plugin-completion-report.md` |
| — | Root Makefile — `make unit`, `make integration`, `make styles`, `make code-rebuild` | ✅ Done | — |

---

## Sprint 01 — vbwd-backend ✅ DONE

**Completed:** 2026-03-14

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Fix `datetime.utcnow()` (30 files) — `src/utils/datetime_utils.py` utcnow() helper | ✅ |
| 2 | Extract UUID validation utility — `src/utils/validation.py`, applied to subscriptions.py | ✅ |
| 3 | Fix bare `except: pass` in GHRM sync — now logs WARNING | ✅ |
| 4 | Hash sync API keys | ⏭ Deferred (requires DB migration) |
| 5 | Consolidate dead `archive_plan` code — delegates to `deactivate_plan` | ✅ |
| 6 | Fix `UserTokenBalance.query` → `db.session.query(...)` in admin/users.py | ✅ |
| 7 | Fix `import re` inside function bodies in admin/plans.py | ✅ |
| 8 | Enforce service factory pattern | ✅ Already correct in all plugins |
| 9 | Add README.md to cms, stripe, yookassa, paypal, chat plugins | ✅ |

### Pre-commit
- [x] `./bin/pre-commit-check.sh --lint` → PASS (Black ✓ Flake8 ✓ Mypy ✓)
- [x] `./bin/pre-commit-check.sh --quick` → PASS (1086 unit tests)
- [ ] `./bin/pre-commit-check.sh` (full — integration test has pre-existing UniqueViolation in ghrm test data)

---

## Sprint 02 — vbwd-fe-admin ✅ DONE

**Completed:** 2026-03-14

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Type the API client — eliminate `(api as any).method(...)` (39 occurrences) | ✅ |
| 2 | Fix `as any` translation casts in CMS admin plugin (8 occurrences) | ✅ |
| 3 | Remove `console.log` + add `no-console` ESLint rule | ✅ |
| 4 | Centralize API error handling | ⏭ Deferred (no Axios interceptor wiring) |
| 5 | Add README.md to all admin plugins | ✅ |
| — | Pre-existing: Fix `RequestInit` type error in `GhrmSoftwareTab.vue` | ✅ |

### Pre-commit
- [x] `./bin/pre-commit-check.sh --style` → PASS (ESLint ✓ TypeScript ✓)
- [x] `./bin/pre-commit-check.sh --unit --integration` → PASS

---

## Sprint 03 — vbwd-fe-user ✅ DONE

**Completed:** 2026-03-14

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Type the CMS API client — eliminate `(api as any).get(...)` (5 occurrences) | ✅ |
| 2 | Extract `registerPluginTranslations` utility | ⏭ Not applicable — sdk.addTranslations() already consistent |
| 3 | Standardize `_active` plugin flag pattern | ⏭ Deferred — passes type check; object-literal TS limitation |
| 4 | Remove `console.log` + add `no-console` ESLint rule | ✅ |
| 5 | Centralize API error handling (incl. 402 → /plans) | ⏭ Deferred (no Axios interceptor setup) |
| 6 | Add README.md to all user plugins (9 plugins) | ✅ |
| — | Pre-existing: Fix `responseType` TS error in `useCmsStore.ts` | ✅ |
| — | Pre-existing: Install `express-rate-limit` (failing unit test) | ✅ |

### Pre-commit
- [x] `./bin/pre-commit-check.sh --style` → PASS (ESLint ✓ TypeScript ✓)
- [x] `./bin/pre-commit-check.sh --unit --integration` → PASS (283 unit tests ✓)

---

## Sprint 04 — Billing Gaps ✅ DONE

**Completed:** 2026-03-14

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Add `DAILY` billing period — `BillingPeriod.DAILY`, `PERIOD_DAYS[DAILY]=1`, `PERIOD_DAYS[WEEKLY]=7`, `BILLING_PERIOD_TO_STRIPE["DAILY"]`, `BILLING_PERIOD_TO_PAYPAL["daily"]` | ✅ |
| 2 | YooKassa auto-renewal — `YooKassaRenewalService.charge_saved_method()` in `plugins/yookassa/src/services/` | ✅ |
| 3 | YooKassa `payment.canceled` webhook — marks invoice `FAILED`, emits `PaymentFailedEvent` via container dispatcher | ✅ |
| 4 | APScheduler (`APScheduler==3.10.4`) — `src/scheduler.py`, wired in `create_app()`, skipped when `TESTING=True` | ✅ |
| 5 | Dunning — `payment_failed_at` column on Subscription, Alembic migration `f2g3h4i5j6k7`, `find_dunning_candidates()` repo method, `SubscriptionService.send_dunning_emails()`, `SubscriptionDunningEvent`, `PaymentFailedHandler` sets `payment_failed_at` | ✅ |

### Tests Added
- `tests/unit/services/test_subscription_service.py` — `TestBillingPeriodDays` (DAILY=1, WEEKLY=7, all covered), `TestSendDunningEmails` (5 tests)
- `plugins/stripe/tests/test_recurring.py` — `TestBillingPeriodToStripeDaily` (2 tests)
- `plugins/paypal/tests/test_recurring.py` — `TestBillingPeriodToPaypalDaily` (1 test)
- `plugins/yookassa/tests/test_renewal_service.py` — `TestYooKassaRenewalService` (4 tests)
- `plugins/yookassa/tests/test_webhook.py` — `TestPaymentCanceled` (4 tests: marks FAILED, emits event, unknown invoice no-op, no invoice_id no-op)
- `tests/unit/test_scheduler.py` — `TestRunSubscriptionJobs` (4 tests)

### Results
- 733 unit tests passed, 4 skipped

---

## Sprint 05 — Email System ✅ DONE

**Completed:** 2026-03-14

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Backend `email` plugin — `EmailTemplate` model, `IEmailSender`/`EmailMessage` interface, `EmailSenderRegistry`, `SmtpEmailSender`, `EmailService` (Jinja2 rendering), `EVENT_CONTEXTS` (8 events), `seeds.py`, admin API routes (6 endpoints) | ✅ |
| 2 | Backend `mailchimp` plugin — `MandrillEmailSender` (Liskov-substitutable reference implementation) | ✅ |
| 3 | fe-admin `email-admin` plugin — `EmailTemplateList.vue`, `EmailTemplateEdit.vue` (3-tab HTML/Text/Preview), `useEmailStore.ts` | ✅ |
| 4 | fe-admin nav — "Messaging → Email Templates" group added via `extensionRegistry` | ✅ |
| 5 | Mailpit service in `docker-compose.yaml` (port 8025 UI / 1025 SMTP) | ✅ |
| 6 | Alembic migration `20260314_create_email_template_table.py` | ✅ |

### Tests
- 23 unit tests (registry, smtp sender, email service) — all ✅
- 28 integration tests (security, CRUD, preview, migration schema, edge cases) — all ✅
- fe-admin: `emailAdminPlugin.spec.ts` (pluginLoader contract, install/activate/deactivate), `EmailTemplateList.spec.ts`
- Full pre-commit: `--full` → **PASS** (1121 unit ✓, 82 integration ✓, lint ✓)
