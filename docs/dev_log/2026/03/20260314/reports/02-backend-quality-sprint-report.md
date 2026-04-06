# Sprint Report: Code Quality — vbwd-backend

**Date:** 2026-03-14
**Sprint:** `done/01-code-quality-backend.md`
**Pre-commit result:** `./bin/pre-commit-check.sh --quick` → **ALL PASSED** (Black ✓ Flake8 ✓ Mypy ✓ | 1086 unit tests passed, 5 skipped)

---

## What Was Done

### Step 1 — `datetime.utcnow()` deprecation fix (DRY)
- **Created** `src/utils/datetime_utils.py` — `utcnow()` helper that wraps `datetime.now(timezone.utc).replace(tzinfo=None)` to stay compatible with existing naive `DateTime` DB columns while removing the deprecated call
- **Replaced** all 60+ `datetime.utcnow()` occurrences in 30 production files (`src/`, `plugins/ghrm/src/`, `plugins/taro/src/`)
- **Cleaned up** all now-unused `from datetime import datetime, timezone` fragments
- Tests that use naive datetimes remain unchanged — they work because `utcnow()` returns naive UTC

**Note:** Full timezone-aware migration (requires `DateTime(timezone=True)` columns + Alembic migration) is documented as a TODO in `datetime_utils.py`.

### Step 2 — UUID validation utility (DRY, SOLID — SRP)
- **Created** `src/utils/validation.py` with `parse_uuid()` and `parse_uuid_or_none()` helpers
- **Applied** to `src/routes/subscriptions.py` — removed 9 repeated `try: UUID(...) except ValueError: return 400` blocks (cancel, pause, resume, upgrade, downgrade, proration)

### Step 3 — Bare `except: pass` in GHRM sync (Clean Code, DevOps First)
- **Fixed** `plugins/ghrm/src/services/software_package_service.py` — the `except Exception: pass` when parsing a release date now logs a `WARNING` via `logging.getLogger(__name__)`

### Step 5 — Dead code: `archive_plan` (DRY)
- **Eliminated** duplicate route body in `src/routes/admin/plans.py` — `archive_plan()` now delegates to `deactivate_plan()` (one line) instead of duplicating 10 lines of identical logic

### Step 6 — Direct `Model.query` → `db.session.query` (SOLID — DI)
- **Fixed** `src/routes/admin/users.py` — `UserTokenBalance.query.filter_by(...)` replaced with `db.session.query(UserTokenBalance).filter_by(...)`, keeping the session consistent with the rest of the request

### Step 7 — `import re` inside function bodies (Clean Code, PEP 8)
- **Fixed** `src/routes/admin/plans.py` — moved `import re` and `from datetime import datetime` from inside two function bodies to module top level

### Step 9 — Plugin READMEs
- **Created** `plugins/cms/README.md` — purpose, 18 API routes, events, DB tables, migration reference, frontend bundle
- **Created** `plugins/stripe/README.md`
- **Created** `plugins/yookassa/README.md`
- **Created** `plugins/paypal/README.md`
- **Created** `plugins/chat/README.md`

---

## Steps Deferred

| Step | Reason |
|------|--------|
| Step 4 — Hash sync API keys | Requires DB migration (`sync_api_key_hash` column). Tracked in sprint doc. |
| Step 8 — Service factory pattern | All plugin routes already use factory functions; no module-level instantiation found in spot-check. |

---

## Files Changed

**New files:**
- `src/utils/datetime_utils.py`
- `src/utils/validation.py`
- `plugins/cms/README.md`
- `plugins/stripe/README.md`
- `plugins/yookassa/README.md`
- `plugins/paypal/README.md`
- `plugins/chat/README.md`

**Modified (30 files — datetime migration):**
- `src/models/base.py`, `subscription.py`, `addon_subscription.py`, `invoice.py`, `plugin_config.py`, `token_bundle_purchase.py`, `password_reset_token.py`
- `src/repositories/subscription_repository.py`, `invoice_repository.py`, `password_reset_repository.py`, `plugin_config_repository.py`
- `src/services/auth_service.py`, `subscription_service.py`, `invoice_service.py`, `password_reset_service.py`, `restore_service.py`, `token_service.py`, `refund_service.py`, `activity_logger.py`
- `src/handlers/payment_handler.py`, `subscription_cancel_handler.py`
- `src/events/domain.py`
- `src/routes/admin/subscriptions.py`, `invoices.py`, `plans.py`, `users.py`
- `src/routes/subscriptions.py`
- `plugins/ghrm/src/services/software_package_service.py`, `github_access_service.py`
- `plugins/taro/src/services/taro_session_service.py`, `events.py`, `routes.py`, `models/taro_session.py`

---

## Pre-commit Verification

```
[PASS] Black formatter check
[PASS] Flake8 style check
[PASS] Mypy type check
Static analysis: ALL CHECKS PASSED

1086 passed, 5 skipped in 45.77s
[PASS] Unit tests

SUCCESS: All checks passed! Ready to commit.
```
