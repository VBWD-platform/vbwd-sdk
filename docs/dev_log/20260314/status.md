# Sprint Status — 2026-03-14

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 01 | Code Quality — vbwd-backend | ✅ Done | `reports/02-backend-quality-sprint-report.md` |
| 02 | Code Quality — vbwd-fe-admin | ✅ Done | `reports/03-fe-admin-quality-sprint-report.md` |
| 03 | Code Quality — vbwd-fe-user | ✅ Done | `reports/04-fe-user-quality-sprint-report.md` |
| 04 | Billing Gaps — recurring billing & subscription lifecycle | ⏳ Pending approval | — |
| 05 | Email System — templates, SMTP, Mailchimp demo, Mailpit | ⏳ Pending approval | — |
| — | GHRM Production Fix — real GitHub client, 500 on catalogue, mock cleanup | ✅ Done | `reports/05-ghrm-production-fix-report.md` |
| — | Root Makefile — `make unit`, `make integration`, `make styles` | ✅ Done | — |

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

## Sprint 04 — Billing Gaps ⏳ PENDING APPROVAL

**Sprint doc:** `sprints/04-billing-gaps.md`

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Add `DAILY` billing period — enums, PERIOD_DAYS, Stripe + PayPal interval maps | ⏳ |
| 2 | YooKassa auto-renewal — charge saved payment method on renewal | ⏳ |
| 3 | YooKassa `payment.canceled` webhook handler — emit `PaymentFailedEvent` | ⏳ |
| 4 | Auto-invoke `expire_subscriptions()` + `expire_trials()` via APScheduler | ⏳ |
| 5 | Dunning email sequence — day 3 + day 7 follow-ups via `payment_failed_at` field | ⏳ |

---

## Sprint 05 — Email System ⏳ PENDING APPROVAL

**Sprint doc:** `sprints/05-email-system.md`

### Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Backend `email` plugin — model, service, SMTP sender, event contexts, admin API routes | ⏳ |
| 2 | Backend `mailchimp` plugin — Mandrill transport demo (reference implementation) | ⏳ |
| 3 | fe-admin `email-admin` plugin — CodeMirror HTML/text editor, preview tabs | ⏳ |
| 4 | fe-admin settings — "Integrations → Email" tab (SMTP config, sender selector, log flag) | ⏳ |
| 5 | Mailpit service in `docker-compose.yaml` for local email testing | ⏳ |
| 6 | fe-admin navigation — "Email Templates" link under new "Messaging" group | ⏳ |
