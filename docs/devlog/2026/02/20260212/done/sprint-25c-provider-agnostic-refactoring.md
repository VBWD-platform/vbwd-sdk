# Sprint 25c: Provider-Agnostic Refactoring

## Goal
Refactor all core code to be provider-agnostic. No `stripe_*` or `paypal_*` references in `src/` — only in `plugins/`.

## Tasks
1. Rename model columns: `stripe_customer_id` → `payment_customer_id`, merge `stripe_subscription_id` + `paypal_subscription_id` → `provider_subscription_id`, merge `stripe_invoice_id` + `paypal_order_id` → `provider_session_id`
2. Merge repository finders into generic methods
3. Replace direct provider imports in admin refund route with plugin system
4. Update all plugin code and tests to use new names
5. Create Alembic migration with data merge + column rename
6. Fix invoice-pending bug (store provider_session_id at create-session)
7. Fix admin refund not calling provider API

## Acceptance Criteria
- Zero provider-specific names in `src/` directory
- All 792 backend tests pass
- Migration has working upgrade() and downgrade()
