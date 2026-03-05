# Architecture Gaps — Implementation vs. Design

**Priority:** Reference document for planning
**Source:** Comparison of architecture docs vs. actual codebase (2026-02-07)

---

## Admin Frontend Gaps (architecture_core_view_admin)

### Structural

- [ ] **Plugin Architecture** — Architecture defines payment integration plugins (Stripe, PayPal) via plugin system. Admin app uses flat structure for all features
- [ ] **Service Interfaces / DI** — Architecture describes constructor-based DI with service interfaces. Stores call API directly without service layer abstraction

### Feature

- [ ] **Webhook Retry UI** — Architecture sprint-05 describes manual retry, delivery logs, response inspection. Current WebhookDetails.vue scope unclear
- [ ] **Settings Management** — Architecture sprint-05 describes system settings (email templates, notification preferences, payment config). Settings.vue exists but scope limited
- [ ] **User Activity Logs** — Architecture sprint-01 describes detailed activity logging per user. Not visible in admin views
- [ ] **Plan Feature Management** — Architecture sprint-02 describes feature limit configuration UI, Stripe/PayPal sync. PlanForm.vue exists but sync not implemented

---

## User Frontend Gaps (architecture_core_view_user)

### Critical

- [ ] **i18n / Localization** — Admin app has i18n. User app has ZERO i18n configuration. Reduce active languages to EN and DE, keep other translation files but disable them
- [ ] **Cart AddToCart broken** — AddOns and Tokens pages: AddToCart buttons do not work
- [ ] **Checkout total price bug** — Prices are string-concatenated instead of summed (e.g. `$29015.0025.00` instead of `$69.00`)
- [ ] **Checkout button inactive** — Confirm checkout button is disabled / not clickable even when form should be valid

### Feature (from architecture sprints)

- [ ] **Wizard Plugin** (Sprint 2) — Multi-step onboarding wizard described in architecture. Plugin exists but integration unclear
- [ ] **Access Control E2E** (Sprint 5) — Feature gating based on subscription tier. Core has `FeatureGate.vue` and `UsageLimit.vue` components but not used in user app
- [ ] **Real-time Updates** — socket.io-client dependency installed, WebSocket proxy configured in nginx, but no active WebSocket usage in the app

### Testing

- [ ] **Unit Test Coverage** — Only 4 unit test files in user app (stores only). No component unit tests
- [ ] **Integration Tests** — Zero integration test files (admin has 16)

---

## Core SDK Gaps (architecture_core_view_component)

### From Architecture Sprints

- [ ] **Sprint 3: Authentication Service** — JWT handling, session management described. Auth store exists but commented out in core index.ts exports
- [ ] **Sprint 4: Validation Service** — Zod-based validation with reusable schemas described. Zod is a dependency but validation service not fully exported
- [ ] **Sprint 5: Shared UI Components** — 10 UI components exist. Architecture describes more comprehensive library with variants, theming
- [ ] **Sprint 6: Composables** — Only `useFeatureAccess` exported. Architecture describes useApi, useAuth, useForm, useNotification
- [ ] **Sprint 7: Access Control System** — Guards exist (AuthGuard, RoleGuard). Tariff-based access control described but not implemented
- [ ] **Sprint 8: Integration & Documentation** — No storybook, no component documentation, no usage examples

---

## Cross-Cutting Gaps

| Gap | Backend | Admin | User | Core |
|-----|---------|-------|------|------|
| i18n | 8 langs configured | 8 langs implemented | NOT implemented | No i18n |
| Plugin system | Implemented | Not used | Partial | Implemented |
| Real-time / WebSocket | Socket.IO in deps | Not used | socket.io-client installed | EventBus only |
| Error handling | Result objects | Inconsistent | Inconsistent | Error types defined |
| Documentation | Minimal | None | None | None |
| Accessibility | N/A | Not tested | Not tested | No ARIA |
