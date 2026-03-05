# VBWD-SDK Development State Report

**Date:** 2026-02-07
**Scope:** Full codebase audit comparing architecture documentation to implementation
**Sources:** `architecture_core_server_ce/`, `architecture_core_view_admin/`, `architecture_core_view_user/`, `architecture_core_view_component/`, `vbwd-backend/`, `vbwd-frontend/`

---

## Executive Summary

VBWD-SDK is a SaaS subscription platform with a Python/Flask backend and Vue.js 3 frontend (admin + user apps + shared core SDK). The core subscription billing pipeline — user management, tariff plans, subscriptions, invoicing, token bundles, and add-ons — is implemented and tested end-to-end. The architecture documentation describes a significantly larger scope; roughly **60-65% of the planned backend** and **50-55% of the planned frontend** features are implemented.

**Current blockers (frontend):**
1. Checkout total price bug — string concatenation instead of number sum (`$29015.0025.00` instead of `$69.00`)
2. Checkout confirm button inactive
3. AddToCart buttons not working on AddOns and Tokens pages (cart store reactivity)
4. User app missing i18n (admin has EN + DE, user app has none)

---

## 1. Backend — `vbwd-backend/`

### 1.1 Architecture Compliance

| Layer | Architecture Spec | Implementation | Status |
|-------|------------------|----------------|--------|
| Routes → Services → Repos → Models | 4-layer with DI | Fully implemented | ✅ |
| Dependency Injection | `dependency-injector` | Used via containers | ✅ |
| Event-Driven Architecture | Domain events + handlers | EventDispatcher + 5 handler modules | ✅ |
| Plugin System | BasePlugin + PluginManager + lifecycle | Implemented with mock provider | ✅ |
| SDK Adapter Pattern | IPaymentProviderAdapter | Interface + MockAdapter | ⚠️ |
| Webhook System | Event dispatch + retry | Webhook service + routes | ✅ |

### 1.2 Data Model Coverage

| Model (Architecture) | Implemented | Notes |
|----------------------|-------------|-------|
| User + UserDetails | ✅ | email, password, status, role, billing address |
| Role (RBAC) | ✅ | USER, ADMIN, VENDOR |
| TarifPlan + TarifPlanPrice | ✅ | Multi-currency pricing, billing periods |
| Subscription | ✅ | Full lifecycle (PENDING → ACTIVE → CANCELLED → EXPIRED) |
| UserInvoice + InvoiceLineItem | ✅ | Subscription, token bundle, add-on line types |
| Currency | ✅ | Exchange rates, multi-currency |
| Tax | ✅ | Regional tax configuration |
| PaymentMethod + Translation | ✅ | i18n translations, fee calculation |
| Country | ✅ | Enable/disable, ordering |
| TokenBundle + Purchase + Balance + Transaction | ✅ | Full token economy |
| Addon + AddonSubscription | ✅ | Add-on products and subscriptions |
| PasswordResetToken | ✅ | Token-based password reset |
| FeatureUsage | ✅ | Feature usage tracking |
| UserCase | ✅ | Case/project descriptions |

**Model count:** 35 models implemented (Phase 1 complete)

### 1.3 API Endpoints

**Implemented: 65+ endpoints across 13 route modules**

| Route Module | Endpoints | Status |
|-------------|-----------|--------|
| Auth (register, login, forgot/reset password) | 4 | ✅ |
| User (profile, details, checkout, tokens) | 7 | ✅ |
| Subscriptions (CRUD, upgrade/downgrade/pause/cancel) | 7 | ✅ |
| Invoices (list, detail) | 2 | ✅ |
| Tarif Plans (list, by slug) | 2 | ✅ |
| Add-ons (list) | 1 | ✅ |
| Token Bundles (list) | 1 | ✅ |
| Settings (countries, payment methods, terms) | 4 | ✅ |
| Config (languages) | 1 | ✅ |
| Webhooks (payment, test) | 2 | ✅ |
| Events (log, types) | 2 | ✅ |
| Admin (users, plans, subscriptions, invoices, addons, token bundles, payment methods, countries, analytics, profile, settings) | 30+ | ✅ |

### 1.4 Services

**14 service classes** covering:
- AuthService, UserService, SubscriptionService, TarifPlanService
- InvoiceService, CurrencyService, TaxService
- PasswordResetService, EmailService
- ActivityLogger, FeatureGuard, RBACService, TokenService

### 1.5 Testing

| Category | Files | Status |
|----------|-------|--------|
| Unit tests | 43 | ✅ |
| Integration tests | 13 | ✅ |
| Fixtures / helpers | 4 | ✅ |
| **Total** | **60** | |

Coverage areas: services, events, handlers, plugins, routes, schemas, webhooks, SDK, infrastructure.

### 1.6 Infrastructure

- Docker Compose: 6 services (api, postgres, redis, adminer, test, test-integration)
- 6 Alembic migrations (initial schema through payment methods)
- Makefile with 15+ commands
- Health checks for postgres and redis
- Multi-environment config (dev, test, production)

### 1.7 Backend Gaps

Backend is feature-complete for current development phase. Future roadmap items (payment providers, Celery tasks, PDF generation, production email, advanced analytics, API docs) are documented in `reports/backend-future-roadmap.md`.

---

## 2. Admin Frontend — `vbwd-frontend/admin/vue/`

### 2.1 Architecture Compliance

| Feature (Architecture) | Implementation | Status |
|------------------------|----------------|--------|
| Hybrid architecture (flat core + plugins) | Flat structure only | ⚠️ |
| Router with auth guards | 30+ routes with meta guards | ✅ |
| Pinia state management | 11 stores | ✅ |
| i18n (vue-i18n) | 8 languages implemented | ✅ |
| E2E testing (Playwright) | 34 spec files | ✅ |
| Unit testing (Vitest) | 7 test files | ✅ |

### 2.2 Views (20 implemented)

| View | Architecture Sprint | Status |
|------|-------------------|--------|
| Login | Sprint 0 | ✅ |
| Dashboard | Sprint 0 | ✅ |
| Users / UserDetails / UserCreate / UserEdit | Sprint 1 | ✅ |
| Plans / PlanForm | Sprint 2 | ✅ |
| Subscriptions / SubscriptionCreate / SubscriptionDetails | Sprint 3 | ✅ |
| Invoices / InvoiceDetails | Sprint 3 | ✅ |
| Analytics | Sprint 4 | ✅ |
| Settings (webhooks, token bundles) | Sprint 5 | ✅ |
| PaymentMethods / PaymentMethodForm | Added 2026-01-22 | ✅ |
| Countries | Added 2026-01-22 | ✅ |
| Profile | Added | ✅ |
| AddOns | Added | ✅ |
| Forbidden (403) | Added | ✅ |

### 2.3 Admin Gaps

| Gap | Details |
|-----|---------|
| Plugin system not used | Architecture describes Stripe/PayPal integration plugins |
| Service layer abstraction | Stores call API directly; no injectable service interfaces |
| User activity logs UI | Sprint 1 describes per-user activity timeline |
| Plan sync with Stripe/PayPal | Sprint 2 describes payment provider plan synchronization |
| Webhook retry UI details | Sprint 5 describes manual retry, delivery log inspection |
| Storybook / component docs | Not implemented |

---

## 3. User Frontend — `vbwd-frontend/user/vue/`

### 3.1 Architecture Compliance

| Feature (Architecture) | Implementation | Status |
|------------------------|----------------|--------|
| Vue.js 3 + Pinia + Vue Router | Fully set up | ✅ |
| Authentication with session handling | JWT + session expiry modal | ✅ |
| Checkout flow (multi-step) | Email, billing, payment, terms blocks | ✅ |
| i18n | **NOT implemented** | ❌ |
| Plugin system | Scaffolded, not active | ⚠️ |
| E2E testing | 18 spec files | ✅ |

### 3.2 Views (11 implemented)

| View | Architecture Sprint | Status |
|------|-------------------|--------|
| Login | Sprint 1 | ✅ |
| Dashboard | Sprint 0 | ✅ |
| Profile | Sprint 4 | ✅ |
| Subscription | Sprint 4 | ✅ |
| Invoices / InvoiceDetail / InvoicePay | Sprint 4 | ✅ |
| Plans | Sprint 3 | ✅ |
| Checkout | Sprint 3 | ✅ |
| AddOns | Added 2026-01-30 | ✅ |
| Tokens | Added 2026-01-30 | ✅ |
| Wizard (onboarding) | Sprint 2 | ⚠️ Plugin exists, not integrated |
| Ticket Management | Sprint 6 | — Future |
| Booking Management | Sprint 7 | — Future |

### 3.3 Checkout Components (from 2026-01-22 session)

| Component | Status |
|-----------|--------|
| EmailBlock.vue | ✅ Email verification with login/register |
| BillingAddressBlock.vue | ✅ Address form with country selection |
| PaymentMethodsBlock.vue | ✅ Payment method radio selection |
| TermsCheckbox.vue | ✅ Terms agreement with popup |

### 3.4 User App Gaps

| Gap | Severity | Details |
|-----|----------|---------|
| i18n | **Critical** | Admin has EN + DE active, user app has none. Reduce to EN + DE, keep other translation files disabled |
| Checkout total price | **Critical** | Prices string-concatenated instead of summed (`$29015.0025.00`). Number type conversion needed |
| Checkout button inactive | **Critical** | Confirm button disabled even when user is logged in and order populated |
| Cart store reactivity | **High** | Pinia import from core SDK breaks reactivity; AddToCart buttons non-functional; 14 E2E tests failing |
| Unit test coverage | Medium | Only 4 test files (stores). No component tests |
| Integration tests | Medium | Zero integration test files |
| Plugin integration | Medium | Wizard plugin exists but not wired into app |
| WebSocket usage | Low | socket.io-client installed, not used |
| Access control (feature gating) | Low | Core has FeatureGate/UsageLimit, not used in user app |

### 3.5 E2E Test Status

| Category | Tests | Status |
|----------|-------|--------|
| Admin E2E | 268 | ✅ All passing (as of 2026-01-23) |
| User E2E — Checkout | 25 | ✅ All passing (fixed 2026-01-30) |
| User E2E — Plans/Tokens/AddOns | 29 | ⚠️ 15 passing, 14 failing (cart reactivity) |
| User E2E — Other (profile, subscription, invoices) | ~20 | ⚠️ 5 failing (missing testids/UI) |

---

## 4. Core SDK — `vbwd-frontend/core/`

### 4.1 Architecture Compliance

| Module (Architecture) | Implementation | Status |
|----------------------|----------------|--------|
| Plugin System (Registry, SDK, lifecycle) | Implemented with tests | ✅ |
| API Client (Axios, interceptors) | Implemented with tests | ✅ |
| Guards (Auth, Role) | Implemented with tests | ✅ |
| Event Bus | Implemented with tests | ✅ |
| UI Components (10 base) | 10 components implemented | ✅ |
| Cart Components (4) | Implemented | ✅ |
| Form Components (3) | Implemented | ✅ |
| Layout Components (3) | Implemented | ✅ |
| Access Control Components (2) | Implemented | ✅ |
| Stores (auth, cart, subscription) | Implemented | ✅ |
| Authentication Service | Auth store exists, export commented out | ⚠️ |
| Validation Service (Zod) | Zod dependency, service not fully exported | ⚠️ |
| Composables (useApi, useAuth, useForm, useNotification) | Only useFeatureAccess exists | ⚠️ |
| Access Control (tariff-based) | Guards exist, tariff-based logic not implemented | ⚠️ |
| Storybook / Component docs | Not implemented | ❌ |

### 4.2 Core SDK Gaps

| Gap | Details |
|-----|---------|
| Composables incomplete | Architecture describes 4+ composables; only 1 exists |
| Auth service export | Commented out in index.ts |
| Validation service | Zod available but no shared validation schemas exported |
| Theming / design tokens | No design system, no theme configuration |
| Component documentation | No storybook or living docs |

---

## 5. Cross-Component Analysis

### 5.1 Implementation Maturity by Feature

| Feature | Backend | Admin FE | User FE | Core SDK | Overall |
|---------|---------|----------|---------|----------|---------|
| Authentication | ✅ | ✅ | ✅ | ✅ | **Complete** |
| User Management | ✅ | ✅ | ✅ | ✅ | **Complete** |
| Tariff Plans | ✅ | ✅ | ✅ | — | **Complete** |
| Subscriptions | ✅ | ✅ | ✅ | ⚠️ | **Mostly Complete** |
| Invoicing | ✅ | ✅ | ✅ | — | **Complete** |
| Token Bundles | ✅ | ✅ | ✅ | — | **Complete** |
| Add-ons | ✅ | ✅ | ✅ | — | **Complete** |
| Checkout Flow | ✅ | — | ✅ | ⚠️ cart | **Mostly Complete** |
| Payment Providers | ⚠️ mock | ⚠️ no sync | ⚠️ no flow | ⚠️ interface | **Not Ready** |
| Analytics | ⚠️ basic | ✅ view | — | — | **Basic** |
| Webhooks | ✅ | ✅ | — | — | **Complete** |
| i18n | ✅ 8 langs | ✅ EN+DE active | ❌ | — | **Incomplete** |
| Plugin System | ✅ | ❌ not used | ⚠️ scaffolded | ✅ | **Partial** |
| Event System | ✅ | — | — | ✅ bus | **Backend Complete** |
| Booking/Tickets | — | — | — | — | **Future** |

### 5.2 Test Coverage Summary

| Component | Unit | Integration | E2E | Total |
|-----------|------|-------------|-----|-------|
| Backend | 43 | 13 | — | 56 + 4 fixtures |
| Admin FE | 7 | 16 | 34 | 57 |
| User FE | 4 | 0 | 18 | 22 |
| Core SDK | 18 | 2 | — | 20 |
| **Total** | **72** | **31** | **52** | **~159** |

---

## 6. Recommendations (Current Sprint Priorities)

### Sprint 01 — Checkout Page Bugs (HIGH)

1. **Fix total price calculation** — Convert price values to numbers before summing. String concatenation producing `$29015.0025.00` instead of `$69.00`
2. **Fix checkout button** — Investigate `canPay` / disabled condition. Button should be active when user is logged in, order exists, billing address filled, payment method selected, terms accepted
3. **Pre-fill email for logged-in users**

### Sprint 02 — AddToCart Fix (HIGH)

4. **Fix cart store reactivity** — AddToCart buttons non-functional on AddOns and Tokens pages. Cart store from `@vbwd/view-component` loses Pinia reactivity. See `reports/cart-store-fix.md` for solution approaches

### Sprint 03 — User App i18n (HIGH)

5. **Add i18n to user app** — Copy pattern from admin. Active languages: EN + DE only. Keep other translation files but disabled

### Sprint 04 — E2E Test Fixes (MEDIUM)

6. **Fix 5 remaining user E2E failures** — Profile testids, usage stats, invoice modal, payment page. See `reports/user-e2e-fixes.md`

### Future (see `reports/backend-future-roadmap.md`)

Backend production readiness items (payment providers, Celery, PDF, email, analytics, API docs) tracked separately.

---

## 7. Architecture Debt

| Debt | Impact | Recommendation |
|------|--------|----------------|
| Admin flat structure vs. planned plugin architecture | Low — current approach works, adds simplicity | Keep flat for core features; use plugins only for payment integrations |
| Core SDK exports commented out | Medium — auth, validation not shared properly | Uncomment and wire up in next sprint |
| Inconsistent error handling (stores) | Medium — different patterns across stores | Standardize with shared error handling composable |
| No service layer in frontend | Low — stores call API directly | Acceptable for current size; reconsider if complexity grows |
| Duplicate code between apps | Medium — some patterns repeated | Move shared logic to core SDK composables |

---

*Report generated from codebase analysis on 2026-02-07. See `todo/` folder for actionable items.*
