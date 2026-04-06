# Sprint Plan: 2025-12-29

**Goal:** Complete backend services and fix code quality issues

---

## Core Development Principles

### 1. TDD-First (Test-Driven Development)
```
RED    → Write failing test
GREEN  → Write minimal code to pass
REFACTOR → Improve without breaking tests
```
- Never write production code without a failing test
- Target: 95%+ test coverage for new code

### 2. SOLID Principles
- **S**ingle Responsibility: One class = one job
- **O**pen/Closed: Extend via interfaces, don't modify
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: Small, focused interfaces
- **D**ependency Inversion: Inject dependencies

### 3. Clean Code
- Meaningful names (no abbreviations)
- Small functions (< 20 lines)
- No magic numbers (use constants)
- No duplication (DRY)
- Comments explain WHY, not WHAT

### 4. Dockerized Development
- All code runs in containers
- Tests: `docker-compose run --rm python-test pytest`
- No local Python dependencies required

### 5. No Over-Engineering
- Implement only what's needed NOW
- YAGNI (You Aren't Gonna Need It)
- Simplest solution that works

---

## Task Overview

| # | Task | Current | Target | Priority | Time |
|---|------|---------|--------|----------|------|
| 1 | Invoice Service | 40% | 100% | HIGH | 3-4h |
| 2 | Email Service | 0% | 100% | HIGH | 3-4h |
| 3 | Admin API | 20% | 100% | HIGH | 4-5h |
| 4 | Subscription Enhancement | 70% | 100% | MEDIUM | 2-3h |
| 5 | Backend Cleanup & Security | - | 100% | CRITICAL | 2-3h |
| 6 | Frontend SDK Integration | 0% | 100% | HIGH | 4-5h |
| 7 | Docker Secrets | - | 100% | MEDIUM | 1-2h |

**Total Estimated Time:** 20-26 hours

---

## Execution Order

### Phase 1: Backend Foundation (Tasks 1, 5)
Priority: CRITICAL/HIGH

1. **Task 5: Security Fixes** - Fix critical vulnerabilities first
   - Enable DI container
   - Add rate limiting
   - Fix secret key validation

2. **Task 1: Invoice Service** - Foundation for billing
   - Create InvoiceService
   - Add invoice routes
   - Write tests

### Phase 2: Backend Features (Tasks 2, 3, 4)
Priority: HIGH/MEDIUM

3. **Task 2: Email Service** - Enable notifications
   - Create EmailService
   - Create templates
   - Wire to event handlers

4. **Task 3: Admin API** - Management interface
   - User management
   - Subscription management
   - Invoice management
   - Plan management

5. **Task 4: Subscription Enhancement** - Complete features
   - Pause/Resume
   - Upgrade/Downgrade

### Phase 3: Frontend & DevOps (Tasks 6, 7)
Priority: HIGH/MEDIUM

6. **Task 6: Frontend SDK Integration** - Bridge the gap
   - Link Core SDK to apps
   - Refactor stores
   - Add tests

7. **Task 7: Docker Secrets** - Production ready
   - Environment files
   - Production compose

---

## Quick Commands

```bash
# Navigate to backend
cd /home/dtkachev/dantweb/vbwd-sdk/vbwd-backend

# Run all tests
docker-compose run --rm python-test pytest tests/ -v

# Run specific test file
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py -v

# Run with coverage
docker-compose run --rm python-test pytest tests/ --cov=src --cov-report=html

# Check linting
docker-compose run --rm python-test flake8 src/

# View logs
docker-compose logs -f api
```

---

## Definition of Done

Each task is complete when:

- [ ] All tests written BEFORE implementation (TDD)
- [ ] All tests pass
- [ ] Test coverage ≥ 95% for new code
- [ ] No linting errors (`flake8 src/`)
- [ ] Type hints on all public methods
- [ ] Docstrings on all public classes/methods
- [ ] Code follows SOLID principles
- [ ] Runs in Docker without errors
- [ ] Code reviewed

---

## Files by Task

### Task 1: Invoice Service
- `src/services/invoice_service.py` - CREATE
- `src/routes/invoices.py` - CREATE
- `tests/unit/services/test_invoice_service.py` - CREATE
- `tests/unit/routes/test_invoice_routes.py` - CREATE

### Task 2: Email Service
- `src/services/email_service.py` - CREATE
- `src/templates/email/*.html` - CREATE (8 templates)
- `tests/unit/services/test_email_service.py` - CREATE
- `src/handlers/*.py` - UPDATE (wire email)

### Task 3: Admin API
- `src/routes/admin/__init__.py` - CREATE
- `src/routes/admin/users.py` - CREATE
- `src/routes/admin/subscriptions.py` - CREATE
- `src/routes/admin/invoices.py` - CREATE
- `src/routes/admin/plans.py` - CREATE
- `tests/unit/routes/test_admin_*.py` - CREATE (4 files)

### Task 4: Subscription Enhancement
- `src/services/subscription_service.py` - UPDATE
- `src/routes/subscriptions.py` - UPDATE
- `tests/unit/services/test_subscription_service.py` - UPDATE

### Task 5: Backend Cleanup
- `src/config.py` - UPDATE
- `src/container.py` - UPDATE
- `src/extensions.py` - UPDATE
- `src/routes/*.py` - UPDATE (use DI)
- `src/utils/transaction.py` - CREATE

### Task 6: Frontend SDK Integration
- `user/vue/src/stores/*.js` - UPDATE
- `admin/vue/src/stores/*.js` - UPDATE
- `*/vue/tests/unit/*.spec.js` - CREATE
- `*/vue/vitest.config.js` - CREATE

### Task 7: Docker Secrets
- `.env.production.example` - CREATE
- `docker-compose.yaml` - UPDATE
- `docker-compose.production.yaml` - CREATE
- `src/utils/startup_check.py` - CREATE

---

## Progress Tracking

Update this section as you complete tasks:

```
[ ] Task 1: Invoice Service
    [ ] Tests written
    [ ] Service implemented
    [ ] Routes implemented
    [ ] All tests passing

[ ] Task 2: Email Service
    [ ] Tests written
    [ ] Service implemented
    [ ] Templates created
    [ ] Handlers wired

[ ] Task 3: Admin API
    [ ] User routes done
    [ ] Subscription routes done
    [ ] Invoice routes done
    [ ] Plan routes done

[ ] Task 4: Subscription Enhancement
    [ ] Pause/Resume done
    [ ] Upgrade/Downgrade done

[ ] Task 5: Backend Cleanup
    [ ] Security fixes done
    [ ] DI container enabled
    [ ] Clean code fixes done

[ ] Task 6: Frontend SDK Integration
    [ ] Core SDK linked
    [ ] Stores refactored
    [ ] Tests added

[ ] Task 7: Docker Secrets
    [ ] Env files created
    [ ] Compose updated
```

---

## Notes

- Start with security fixes (Task 5) - they're critical
- Invoice service (Task 1) is foundation for payments
- Email service (Task 2) enables user notifications
- Admin API (Task 3) is large but straightforward
- Frontend integration (Task 6) can be parallelized with backend work
