# Backend — Future Roadmap Items

**Date:** 2026-02-07
**Status:** Not priorities for current sprint. Collected here for future planning.

---

## Production Readiness (Future)

- [ ] **Real Payment Providers** — Architecture defines Stripe, PayPal, Klarna, SEPA, Invoice/Bank Transfer plugins. Only `MockPaymentPlugin` exists in `src/plugins/providers/`
- [ ] **Scheduled Tasks / Celery** — Celery + Redis configured in requirements.txt and config.py but no tasks defined. Needed for: subscription renewals, invoice reminders, payment retries, expiration processing
- [ ] **PDF Invoice Generation** — Admin routes expect PDF export (`/admin/invoices/{id}/pdf`) but no PDF library or generation logic implemented
- [ ] **Real Email Delivery** — EmailService with 9 template types exists but uses mock/dev configuration. Needs production SMTP setup

## Feature Completeness (Future)

- [ ] **Advanced Analytics** — Architecture describes MRR, ARR, churn rate, cohort analysis, revenue charts, export. Only basic dashboard metrics (MRR, total revenue, user count, active subscriptions) implemented
- [ ] **API Documentation** — No Swagger/OpenAPI spec. Architecture mentions API docs
- [ ] **Audit Logging** — ActivityLogger service exists but not consistently applied across all admin operations
- [ ] **Rate Limiting Tuning** — Flask-Limiter installed, basic limiting on some routes. Architecture describes per-endpoint rate limits
- [ ] **Database Caching** — Redis configured but not used for query caching or session management beyond JWT
- [ ] **WebSocket** — Flask-SocketIO in deps, not used
- [ ] **Load Testing** — Locust in deps, no scenarios
