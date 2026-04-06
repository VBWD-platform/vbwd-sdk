# Sprint Plan: 2025-12-30 to 2026-01-06

**Goal:** Address remaining code review issues - Security, Architecture, and Features

---

## Core Development Requirements

**MANDATORY for all sprints - no exceptions:**

### 1. TDD-First (Test-Driven Development)
```
RED    → Write failing test FIRST
GREEN  → Write MINIMAL code to pass
REFACTOR → Improve without breaking tests
```
- Tests MUST be written BEFORE implementation
- No code without a failing test first
- Test coverage ≥ 80% for new code

### 2. SOLID Principles
- **S**ingle Responsibility: One class = one reason to change
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable for base types
- **I**nterface Segregation: Many specific interfaces > one general
- **D**ependency Inversion: Depend on abstractions, not concretions

### 3. Dependency Injection (DI)
- All dependencies injected via constructor
- Use DI container for service resolution
- No `new` keyword in business logic
- Mock dependencies in tests

### 4. Clean Code
- Meaningful, descriptive names
- Small functions (<20 lines)
- No magic numbers/strings
- No duplication (DRY)
- Self-documenting code

### 5. No Over-Engineering
- YAGNI: Don't build what you don't need NOW
- Solve the current problem, not hypothetical future ones
- Simple solutions > clever solutions
- No premature optimization
- No unnecessary abstractions

---

## Architecture Notes

### Event-Driven Architecture (CRITICAL)

**The correct flow:**
```
Request → Route (emit event) → Event Dispatcher → Handler(s) → Services → Database
```

**Key principles:**
1. **Routes emit events** - Routes do NOT call services directly
2. **Dispatcher routes** - Dispatcher routes events to registered handlers
3. **Handlers orchestrate** - Handlers call services and perform side effects
4. **Services are pure** - Services contain business logic only, NO event emission
5. **Decoupled** - Each layer only knows about the next layer

**Example:**
```
POST /auth/register
    → Route emits UserRegisterEvent
    → Dispatcher finds UserHandler
    → UserHandler.handle_register():
        → calls UserService.create_user()
        → calls EmailService.send_welcome()
        → calls SubscriptionService.create_free_tier()
        → returns EventResult
    → Route returns result to client
```

### Plugin Architecture
Payments and other extensible features use a **plugin pattern**:
- Abstract base interface defines contract
- Concrete implementations as plugins
- Registry for plugin discovery
- Easy to add new providers without core changes

---

## Sprint Overview

| Sprint | Focus | Priority | Architecture |
|--------|-------|----------|--------------|
| Sprint 1 | Security Fixes | CRITICAL | Services + Events |
| Sprint 2 | Event System | HIGH | Event Bus pattern |
| Sprint 3 | Payment Integration | HIGH | **Plugin architecture** |
| Sprint 4 | Access Control | HIGH | Guards + Decorators |
| Sprint 5 | UI Components | MEDIUM | Shared library + Plugins |
| Sprint 6 | User Cabinet | MEDIUM | Services |
| Sprint 7 | Admin Management | MEDIUM | Admin routes |
| Sprint 8 | Analytics | LOW | Service + Caching |

---

## Task Breakdown

### Sprint 1: Security Fixes (CRITICAL)
**Duration:** 1 day
**Files:** 01-security-fixes.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 1.1 Password Reset Flow | HIGH | 3-4h |
| 1.2 CSRF Protection | MEDIUM | 2h |
| 1.3 Remove Hardcoded Admin Hint | MEDIUM | 30min |
| 1.4 HttpOnly Cookie Option | LOW | 2h |

### Sprint 2: Event System Completion (HIGH)
**Duration:** 1-2 days
**Files:** 02-event-system.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 2.1 Complete User Handlers | HIGH | 2-3h |
| 2.2 Complete Subscription Handlers | HIGH | 2-3h |
| 2.3 Complete Payment Handlers | HIGH | 2-3h |
| 2.4 Frontend Event Bus | MEDIUM | 3-4h |

### Sprint 3: Payment Integration - PLUGIN ARCHITECTURE (HIGH)
**Duration:** 2-3 days
**Files:** 03-payment-integration.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 3.1 Payment Plugin Base Interface | HIGH | 2-3h |
| 3.2 Stripe Plugin Implementation | HIGH | 4-5h |
| 3.3 Mock Provider for Testing | MEDIUM | 2h |
| 3.4 Payment Service (Plugin Consumer) | HIGH | 2-3h |
| 3.5 Webhook Routes | HIGH | 2h |

### Sprint 4: Access Control (HIGH)
**Duration:** 1-2 days
**Files:** 04-access-control.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 4.1 RBAC Backend Implementation | HIGH | 3-4h |
| 4.2 Tariff-based Guards | HIGH | 2-3h |
| 4.3 Frontend Access Control | HIGH | 3-4h |
| 4.4 Permission Decorators | MEDIUM | 2h |

### Sprint 5: UI Components & Plugins (MEDIUM)
**Duration:** 2 days
**Files:** 05-ui-components.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 5.1 Shared Component Library | MEDIUM | 4-5h |
| 5.2 Plugin Integration in User App | MEDIUM | 3-4h |
| 5.3 Plugin Integration in Admin App | MEDIUM | 3-4h |
| 5.4 Component Documentation | LOW | 2h |

### Sprint 6: User Cabinet (MEDIUM)
**Duration:** 2-3 days
**Files:** 06-user-cabinet.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 6.1 Profile Management | MEDIUM | 3-4h |
| 6.2 Subscription View/Management | MEDIUM | 4-5h |
| 6.3 Invoice History & Download | MEDIUM | 3-4h |
| 6.4 Plan Upgrade/Downgrade UI | MEDIUM | 3-4h |

### Sprint 7: Admin Management (MEDIUM)
**Duration:** 2-3 days
**Files:** 07-admin-management.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 7.1 User Management UI | MEDIUM | 4-5h |
| 7.2 Plan Management UI | MEDIUM | 3-4h |
| 7.3 Subscription Management UI | MEDIUM | 4-5h |
| 7.4 Invoice Management UI | MEDIUM | 3-4h |

### Sprint 8: Analytics Dashboard (LOW)
**Duration:** 2-3 days
**Files:** 08-analytics-dashboard.md

| Task | Priority | Estimated |
|------|----------|-----------|
| 8.1 Backend Analytics Service | LOW | 4-5h |
| 8.2 MRR & Revenue Metrics | LOW | 3-4h |
| 8.3 User & Churn Metrics | LOW | 3-4h |
| 8.4 Dashboard UI | LOW | 4-5h |

---

## Execution Order

### Week 1 (Dec 30 - Jan 1)
- **Sprint 1:** Security Fixes (CRITICAL)
- **Sprint 2:** Event System Completion

### Week 2 (Jan 2 - Jan 4)
- **Sprint 3:** Payment Integration
- **Sprint 4:** Access Control

### Week 3 (Jan 5 - Jan 6+)
- **Sprint 5:** UI Components
- **Sprint 6:** User Cabinet

### Future
- **Sprint 7:** Admin Management
- **Sprint 8:** Analytics Dashboard

---

## Quick Commands

```bash
# Backend tests
cd vbwd-backend
docker-compose --profile test run --rm test pytest tests/unit/ -v

# Frontend tests (after npm install)
cd vbwd-frontend/user/vue
npm test

cd vbwd-frontend/admin/vue
npm test

# Core SDK tests
cd vbwd-frontend/core
npm test
```

---

## Definition of Done

Each task is complete when:
- [ ] Tests written BEFORE implementation (TDD)
- [ ] All tests pass
- [ ] Test coverage ≥ 80% for new code
- [ ] No linting errors
- [ ] Type hints on public methods
- [ ] Docstrings on public classes/methods
- [ ] Code follows SOLID principles
- [ ] Runs in Docker without errors
