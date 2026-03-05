# Sprint 01 — Checkout & Token Balance Bugs

**Priority:** HIGH
**Source:** Manual testing 2026-02-07

## Bug 1: Total Price — String Concatenation

**Symptom:** Total shows `$29015.0025.00` instead of `$69.00` ($29 + $15 + $25)

**Root cause:** API returns prices as strings. The `+=` operator in `orderTotal` concatenates instead of adding.

**File:** `vbwd-frontend/user/vue/src/stores/checkout.ts` lines 87-92
```typescript
const orderTotal = computed(() => {
  let total = plan.value?.price || plan.value?.display_price || 0;  // string "29"
  total += selectedBundles.value.reduce((sum, b) => sum + b.price, 0);  // "29" + "015.00"
  total += selectedAddons.value.reduce((sum, a) => sum + a.price, 0);   // "29015.00" + "25.00"
  return total;  // "29015.0025.00"
});
```

**Fix:** Convert prices to numbers: `Number(plan.value?.price)`, `Number(b.price)`, `Number(a.price)`

---

## Bug 2: Admin Mark-Paid Does NOT Credit Tokens

**Symptom:** Admin marks invoice as paid, but user's token balance stays at 0. No tokens credited, no transaction record created.

**Root cause:** Admin endpoint does not dispatch `PaymentCapturedEvent`. Without the event, `PaymentCapturedHandler` is never triggered, so tokens are never credited.

**File:** `vbwd-backend/src/routes/admin/invoices.py` lines 201-239

The endpoint calls `invoice_service.mark_paid()` but stops there. Compare:
| Endpoint | Dispatches `PaymentCapturedEvent`? | Tokens credited? |
|----------|-----------------------------------|-----------------|
| Admin mark-paid (`/admin/invoices/<id>/mark-paid`) | **NO** | **NO** |
| Webhook (`/webhooks/payment`) | YES | YES |
| User pay (`/user/invoices/<id>/pay`) | YES | YES |

**Fix:** After `invoice_service.mark_paid()` succeeds, dispatch `PaymentCapturedEvent`:
```python
from src.events.payment_events import PaymentCapturedEvent
event = PaymentCapturedEvent(
    invoice_id=UUID(str(result.invoice.id)),
    payment_reference=payment_reference,
    amount=str(result.invoice.amount),
    currency=result.invoice.currency or "USD",
)
dispatcher = current_app.container.event_dispatcher()
dispatcher.emit(event)
```

---

## Bug 3: Dashboard Token Balance Hardcoded to 0

**Symptom:** User's dashboard always shows "0 TKN" even after tokens are credited.

**Root cause:** Dashboard.vue and Profile.vue have placeholder code that returns 0 instead of fetching from API.

**Dashboard.vue** line 164-167:
```typescript
const tokenBalance = computed(() => {
  return 0; // Placeholder - will be fetched from profile details
});
```

**Profile.vue** line 272:
```typescript
const tokenBalance = computed(() => 0); // Will be fetched from user details
```

Only **Subscription.vue** correctly fetches from `/user/tokens/balance`.

**Fix:** Replace placeholders with actual API call (same pattern as Subscription.vue lines 353-361):
```typescript
async function fetchTokenBalance(): Promise<void> {
  try {
    const response = await api.get('/user/tokens/balance') as { balance: number };
    tokenBalance.value = response.balance || 0;
  } catch {
    tokenBalance.value = 0;
  }
}
```

---

## Acceptance Criteria
- [ ] Checkout total correctly sums prices as numbers
- [ ] Admin mark-paid dispatches PaymentCapturedEvent (tokens + subscriptions + addons activated)
- [ ] Dashboard shows real token balance from API
- [ ] Profile shows real token balance from API
- [ ] Pre-commit checks pass
