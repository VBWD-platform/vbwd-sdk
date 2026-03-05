# Sprint 07: Invoice Detail, Payment/Refund Handlers & DB Reset Tool

**Date:** 2026-02-07
**Scope:** Backend + Admin Frontend + User Frontend

---

## Summary

Five areas addressed in this sprint:

1. **Invoice detail pages** now show real line items with type badges and clickable links (admin and user)
2. **Critical payment handler bug** fixed — marking invoice as paid now correctly activates subscriptions, credits tokens, and enables add-ons
3. **Duplicate subscription bug** fixed — activating a new subscription now cancels the previous one
4. **Refund handler** implemented — refunding an invoice now reverses all activated items
5. **Database reset CLI tool** created to replace accumulated test data with a clean demo catalog

---

## 1. Invoice Detail — Real Line Items with Links

### Problem

The admin invoice detail endpoint (`GET /api/v1/admin/invoices/:id`) was overwriting real `InvoiceLineItem` records from the database with a single fake entry:

```python
# vbwd-backend/src/routes/admin/invoices.py (lines 128-136, now deleted)
inv_dict["line_items"] = [{
    "description": inv_dict.get("plan_name", "Subscription"),
    "quantity": 1,
    "unit_price": float(invoice.amount),
    "amount": float(invoice.amount),
}]
```

Both admin and user invoice detail pages displayed line items without type labels or navigation links to the referenced items.

### Solution

**Backend:** Removed the fake line items override. The `invoice.to_dict()` method already returns real line items with `type`, `item_id`, `description`, `quantity`, `unit_price`, and `amount` fields.

**Admin Frontend (`InvoiceDetails.vue`):**
- Added **Type** column with color-coded badges (green=Plan, blue=Token Bundle, pink=Add-On)
- Descriptions are now `<router-link>` elements navigating to item config pages:
  - `subscription` → `/admin/plans/:item_id/edit`
  - `token_bundle` → `/admin/settings/token-bundles/:item_id`
  - `add_on` → `/admin/add-ons`
- Removed redundant "Plan Info" section (plan info now visible as a line item with direct link)
- Added `type` and `item_id` to the `LineItem` TypeScript interface in `stores/invoices.ts`

**User Frontend (`InvoiceDetail.vue`):**
- Same Type column and badge pattern
- Links navigate to user-facing info pages (read-only):
  - `subscription` → `/plans`
  - `token_bundle` → `/tokens`
  - `add_on` → `/addons`
- Added `item_id` to the `LineItem` TypeScript interface

**i18n:** Added `common.type` key — EN: "Type", DE: "Typ"

### Files Changed

| File | Change |
|------|--------|
| `vbwd-backend/src/routes/admin/invoices.py` | Removed fake line_items override (9 lines deleted) |
| `vbwd-frontend/admin/vue/src/views/InvoiceDetails.vue` | Type column, router-links, badges, removed Plan Info section |
| `vbwd-frontend/admin/vue/src/stores/invoices.ts` | Added `type`, `item_id` to `LineItem` interface |
| `vbwd-frontend/user/vue/src/views/InvoiceDetail.vue` | Type column, router-links, badges |
| `vbwd-frontend/admin/vue/src/i18n/locales/en.json` | Added `common.type: "Type"` |
| `vbwd-frontend/admin/vue/src/i18n/locales/de.json` | Added `common.type: "Typ"` |

---

## 2. Payment Handler Bug — "Invoice Already Paid" Short-Circuit

### Problem

When an admin marked an invoice as paid via `POST /api/v1/admin/invoices/:id/mark-paid`, the invoice status updated correctly but **no downstream effects occurred** — subscriptions were not activated, tokens were not credited, and add-ons were not enabled.

### Root Cause

A logic ordering bug in the mark-paid flow:

```
mark_paid route
  ├─ 1. invoice_service.mark_paid()  →  invoice.status = PAID  ✓
  ├─ 2. PaymentCapturedEvent dispatched
  └─ 3. PaymentCapturedHandler.handle()
         ├─ reads invoice  →  sees status == "paid"
         ├─ returns "Invoice already paid"  ✗ (SHORT-CIRCUIT)
         └─ line items NEVER processed
```

The `invoice_service.mark_paid()` on step 1 set the invoice status to `PAID` and persisted it to the same SQLAlchemy session. When the handler ran on step 3, it read the same session object, saw `status == "paid"`, and returned early on line 70-71 without processing any line items.

### Fix

Changed the handler's guard clause from a hard return to a conditional skip:

```python
# BEFORE (broken)
if invoice.status.value == "paid":
    return EventResult.error_result("Invoice already paid")

# AFTER (fixed)
if invoice.status.value != "paid":
    invoice.status = invoice.status.__class__("paid")
    invoice.payment_ref = event.payment_reference
    invoice.paid_at = datetime.utcnow()
    repos["invoice"].save(invoice)
# Line item processing continues regardless
```

The handler now skips only the redundant invoice status update but always processes all line items (subscriptions, token bundles, add-ons).

### File Changed

| File | Change |
|------|--------|
| `vbwd-backend/src/handlers/payment_handler.py` | Removed early return on "already paid", made status update conditional |

---

## 3. Duplicate Subscription Bug — Multiple Active Subscriptions

### Problem

When a user purchased a second plan (e.g., Pro after Basic), the payment handler activated the new subscription without cancelling the existing one. This resulted in two active subscriptions for the same user.

The user frontend is designed for a single active subscription — the store fetches `/user/subscriptions/active` which calls `find_active_by_user()` using `.first()`. With two active subscriptions, it returned whichever the database returned first (the older, cheaper one), hiding the new purchase.

### Fix

The payment handler now cancels any existing active subscription before activating the new one:

```python
# In PaymentCapturedHandler.handle(), subscription activation block:
prev = repos["subscription"].find_active_by_user(invoice.user_id)
if prev and str(prev.id) != str(subscription.id):
    prev.status = SubscriptionStatus.CANCELLED
    prev.cancelled_at = datetime.utcnow()
    repos["subscription"].save(prev)
```

This ensures one active subscription per user at all times, matching the frontend's single-subscription model.

### File Changed

| File | Change |
|------|--------|
| `vbwd-backend/src/handlers/payment_handler.py` | Cancel previous active subscription before activating new one |

---

## 4. Refund Handler — Missing Event-Driven Reversal

### Problem

When an admin refunded an invoice via `POST /api/v1/admin/invoices/:id/refund`, only the invoice status changed to "refunded". **No downstream effects occurred** — the subscription remained active, tokens stayed credited, and add-ons kept running.

The refund endpoint called `invoice_service.mark_refunded()` and returned — no event was dispatched, and no handler existed to reverse the payment effects.

### Root Cause

The refund flow was incomplete — only the "happy path" (payment captured) had event-driven side effects. The reverse path (refund) was never implemented beyond the invoice status change.

Compare the two flows before the fix:

```
mark_paid route (WORKED):
  invoice_service.mark_paid()  →  status = PAID
  PaymentCapturedEvent         →  handler activates subscription/tokens/addons  ✓

refund_invoice route (BROKEN):
  invoice_service.mark_refunded()  →  status = REFUNDED
  (nothing)                        →  subscription still active, tokens still credited  ✗
```

### Fix

Implemented the full refund event chain, mirroring the payment capture pattern:

**1. New event** (`src/events/payment_events.py`):
```python
@dataclass
class PaymentRefundedEvent(DomainEvent):
    invoice_id: UUID
    refund_reference: str
    amount: str
    currency: str = "USD"
    # name = "payment.refunded"
```

**2. New handler** (`src/handlers/refund_handler.py`):

`PaymentRefundedHandler` processes each line item on the refunded invoice:

| Line item type | Reversal action |
|---------------|-----------------|
| `subscription` | Status → CANCELLED, set `cancelled_at` |
| `token_bundle` | Purchase status → REFUNDED, debit tokens from balance, record debit transaction |
| `add_on` | Status → CANCELLED, set `cancelled_at` |

Token debits use `max(0, balance - amount)` to prevent negative balances.

**3. Event dispatch** (`src/routes/admin/invoices.py`):
```python
event = PaymentRefundedEvent(
    invoice_id=UUID(str(result.invoice.id)),
    refund_reference=refund_reference,
    amount=str(result.invoice.amount),
    currency=result.invoice.currency or "USD",
)
dispatcher.emit(event)
```

**4. Handler registration** (`src/app.py`):
```python
refund_handler = PaymentRefundedHandler(container)
dispatcher.register("payment.refunded", refund_handler)
```

### Complete refund flow after fix:

```
refund_invoice route:
  invoice_service.mark_refunded()  →  status = REFUNDED
  PaymentRefundedEvent dispatched
  └─ PaymentRefundedHandler.handle()
     ├─ subscription → CANCELLED
     ├─ token bundles → tokens debited, purchase REFUNDED
     └─ add-ons → CANCELLED
```

### Files Created/Changed

| File | Change |
|------|--------|
| `vbwd-backend/src/events/payment_events.py` | Added `PaymentRefundedEvent` |
| `vbwd-backend/src/handlers/refund_handler.py` | New — reverses subscription, tokens, add-ons |
| `vbwd-backend/src/routes/admin/invoices.py` | Refund endpoint now dispatches `PaymentRefundedEvent` |
| `vbwd-backend/src/app.py` | Registered `PaymentRefundedHandler` |

---

## 5. Database Reset CLI Tool (`flask reset-demo`)

### Problem

The database accumulated ~152 tariff plans, ~73 add-ons, ~56 token bundles, ~247 invoices, and ~242 subscriptions — mostly junk from E2E/integration test runs. The existing `flask cleanup-test-data` only removed `TEST_DATA_` prefixed items, which was insufficient.

### Solution

Created a new `flask reset-demo` CLI command that:

1. **Clears all transactional data** (respecting FK order): token transactions, bundle purchases, addon subscriptions, invoice line items, invoices, subscriptions, token balances, feature usage, password reset tokens
2. **Deletes all catalog items** (plans, addons, token bundles, orphan prices)
3. **Seeds a clean demo catalog:**

| Entity | Items |
|--------|-------|
| Plans | Basic ($9.99/mo), Pro ($29.99/mo), Enterprise ($99.99/mo) |
| Add-ons | Priority Support ($15/mo), Premium Analytics ($25/mo) |
| Token Bundles | Starter 500 ($5), Standard 1000 ($10), Pro 5000 ($45) |

4. **Preserves all user accounts** (61 users untouched)

### Usage

```bash
cd vbwd-backend
make reset-demo                    # one-liner (skips confirmation)
flask --app "src:create_app()" reset-demo       # interactive with confirmation
flask --app "src:create_app()" reset-demo --yes  # skip confirmation
```

### Files Created/Changed

| File | Change |
|------|--------|
| `vbwd-backend/src/cli/reset_demo.py` | CLI command with `--yes` flag |
| `vbwd-backend/src/cli/_demo_seeder.py` | Seeder logic with demo catalog definitions |
| `vbwd-backend/src/cli/__init__.py` | Registered `reset_demo_command` |
| `vbwd-backend/src/app.py` | Registered CLI command with Flask |
| `vbwd-backend/Makefile` | Added `reset-demo` target |

---

## 6. Docker Compose V1 Fix (Root Makefile)

The root `vbwd-sdk/Makefile` used `docker-compose` (V1) which has a known `ContainerConfig` KeyError bug. Replaced all 16 occurrences with `docker compose` (V2).

| File | Change |
|------|--------|
| `vbwd-sdk/Makefile` | `docker-compose` → `docker compose` (all targets) |

---

## Test Results

| Suite | Result |
|-------|--------|
| Backend unit tests | 508 passed, 4 skipped |
| Admin frontend unit tests | 199 passed |
| User frontend unit tests | 40 passed |
| TypeScript build (`vue-tsc`) | Clean after `LineItem` interface fix |

---

## Lessons Learned

1. **Event handler guard clauses must account for the dispatch context.** If the caller already changes state before dispatching, the handler must not treat that state as an error condition. This is a common pitfall in event-driven architectures where the emitter and handler share the same database session.

2. **Every state-changing action needs a reverse action.** Payment capture had an event + handler, but refund had neither. When designing event-driven flows, always implement both the forward and reverse paths together. Same applies to void/cancel operations.

3. **Domain invariants must be enforced at the handler level.** The system's design is one active subscription per user, but neither the checkout handler nor the payment handler enforced this. Relying on the frontend to prevent duplicate subscriptions is insufficient — the backend must cancel the old subscription when activating a new one.

4. **Test data accumulation from E2E runs needs automated cleanup.** The existing `cleanup-test-data` was scoped too narrowly. A full reset tool should be available from day one.

5. **Docker Compose V1 vs V2 matters.** The `docker-compose` binary (V1, Python-based) has unpatched bugs like the `ContainerConfig` KeyError. Always use `docker compose` (V2, Go plugin).

---

## All Files Changed (Sprint 07)

| File | Change |
|------|--------|
| `vbwd-backend/src/routes/admin/invoices.py` | Removed fake line_items, added refund event dispatch |
| `vbwd-backend/src/events/payment_events.py` | Added `PaymentRefundedEvent` |
| `vbwd-backend/src/handlers/payment_handler.py` | Fixed "already paid" short-circuit, cancel previous subscription |
| `vbwd-backend/src/handlers/refund_handler.py` | **New** — reverses subscription, tokens, add-ons on refund |
| `vbwd-backend/src/app.py` | Registered refund handler, reset-demo CLI |
| `vbwd-backend/src/cli/reset_demo.py` | **New** — CLI command |
| `vbwd-backend/src/cli/_demo_seeder.py` | **New** — seeder with demo catalog |
| `vbwd-backend/src/cli/__init__.py` | Registered `reset_demo_command` |
| `vbwd-backend/Makefile` | Added `reset-demo` target |
| `vbwd-frontend/admin/vue/src/views/InvoiceDetails.vue` | Type column, router-links, badges |
| `vbwd-frontend/admin/vue/src/stores/invoices.ts` | Added `type`, `item_id` to `LineItem` |
| `vbwd-frontend/user/vue/src/views/InvoiceDetail.vue` | Type column, router-links, badges |
| `vbwd-frontend/admin/vue/src/i18n/locales/en.json` | `common.type: "Type"` |
| `vbwd-frontend/admin/vue/src/i18n/locales/de.json` | `common.type: "Typ"` |
| `vbwd-sdk/Makefile` | `docker-compose` → `docker compose` |
