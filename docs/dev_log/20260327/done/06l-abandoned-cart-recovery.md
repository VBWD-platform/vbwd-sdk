# Sprint 06l — Abandoned Cart Recovery

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Automatically detect abandoned carts (stock blocked but checkout not completed) and send email reminders to recover lost revenue. Uses core scheduler + email plugin. Admin dashboard shows abandoned cart analytics.

---

## How It Works

```
1. User starts checkout → stock blocked (stock_block created, TTL = 5 min)
2. Stock block expires → scheduler releases stock
3. BUT: the cart data is still in the user's session/backend
4. After 1 hour: scheduler detects "user had items, started checkout, didn't pay"
5. Send email: "You left items in your cart! Complete your purchase."
6. Email contains: product images, names, prices, direct link to cart page
7. After 24 hours: send second reminder (if still not purchased)
8. After 72 hours: final reminder with optional discount incentive
```

---

## Models

**AbandonedCart:**
```python
class AbandonedCart(BaseModel):
    __tablename__ = "ecommerce_abandoned_cart"

    user_id: UUID (FK)
    email: str                          # For guest checkout (if email captured)
    invoice_id: UUID (FK, nullable)     # The unpaid invoice
    cart_data: JSON                     # Snapshot: [{ product_id, variant_id, name, image, price, quantity }]
    cart_total: Numeric(10, 2)
    currency: str
    status: AbandonedCartStatus         # DETECTED, REMINDER_1_SENT, REMINDER_2_SENT, REMINDER_3_SENT, RECOVERED, EXPIRED
    detected_at: DateTime
    reminder_1_at: DateTime             # When first reminder was sent
    reminder_2_at: DateTime
    reminder_3_at: DateTime
    recovered_at: DateTime              # When user completed purchase
    recovery_invoice_id: UUID           # The invoice that completed the recovery
```

**AbandonedCartStatus enum:**
```python
DETECTED = "DETECTED"                   # Cart abandoned, no reminder yet
REMINDER_1_SENT = "REMINDER_1_SENT"     # 1h reminder sent
REMINDER_2_SENT = "REMINDER_2_SENT"     # 24h reminder sent
REMINDER_3_SENT = "REMINDER_3_SENT"     # 72h reminder with discount
RECOVERED = "RECOVERED"                 # User completed purchase
EXPIRED = "EXPIRED"                     # Beyond recovery window (7 days)
```

---

## Services

**AbandonedCartService:**
```python
class AbandonedCartService:
    def detect_abandoned_carts(self) -> list[AbandonedCart]
        """Find users who started checkout but didn't complete.
        Criteria: unpaid invoice with ecommerce line items, older than 1h."""

    def send_reminder(self, abandoned_cart, reminder_level: int) -> None
        """Send email reminder. Level 1=1h, 2=24h, 3=72h+discount."""

    def mark_recovered(self, user_id, invoice_id) -> None
        """Called when user completes purchase. Links recovery."""

    def cleanup_expired(self, max_age_days=7) -> int
        """Mark old abandoned carts as EXPIRED."""

    def get_analytics(self) -> AbandonedCartAnalytics
        """Return: total_abandoned, total_recovered, recovery_rate, revenue_recovered."""
```

**Events:**
```python
"cart.abandoned"        → { user_id, email, cart_total, product_count }
"cart.reminder_sent"    → { user_id, reminder_level }
"cart.recovered"        → { user_id, invoice_id, original_cart_id }
```

---

## Scheduler Jobs

Added to ecommerce scheduler (runs every 5 minutes):

```python
def _run_abandoned_cart_jobs(app):
    with app.app_context():
        service = AbandonedCartService(...)

        # 1. Detect new abandoned carts (unpaid invoices > 1h old)
        new_abandoned = service.detect_abandoned_carts()

        # 2. Send reminders at configured intervals
        # Reminder 1: 1 hour after abandonment
        # Reminder 2: 24 hours
        # Reminder 3: 72 hours (optionally with auto-generated discount code)
        service.send_due_reminders()

        # 3. Cleanup expired (> 7 days)
        service.cleanup_expired()
```

---

## Email Templates

Provided in `docs/imports/email/abandoned-cart-templates.json`:

| Event | Subject | Content |
|-------|---------|---------|
| Reminder 1 (1h) | "You left items in your cart" | Product images, names, prices + "Complete Purchase" CTA button |
| Reminder 2 (24h) | "Still interested? Your cart is waiting" | Same + "Items may sell out" urgency |
| Reminder 3 (72h) | "Last chance — 10% off your cart" | Same + auto-generated coupon code (integrates with 06i discount system) |

---

## Config

**`config.json` (added to ecommerce plugin):**
```json
{
  "abandoned_cart_enabled": true,
  "reminder_1_delay_minutes": 60,
  "reminder_2_delay_minutes": 1440,
  "reminder_3_delay_minutes": 4320,
  "reminder_3_discount_percent": 10,
  "abandoned_cart_expiry_days": 7,
  "abandoned_cart_check_interval_minutes": 5
}
```

**`admin-config.json` (new tab in ecommerce admin config):**
```json
{
  "id": "cart-recovery",
  "label": "Cart Recovery",
  "fields": [
    { "key": "abandoned_cart_enabled", "label": "Enable Cart Recovery", "component": "checkbox" },
    { "key": "reminder_1_delay_minutes", "label": "Reminder 1 Delay (min)", "component": "input", "inputType": "number", "min": 15, "max": 1440 },
    { "key": "reminder_2_delay_minutes", "label": "Reminder 2 Delay (min)", "component": "input", "inputType": "number", "min": 60, "max": 10080 },
    { "key": "reminder_3_delay_minutes", "label": "Reminder 3 Delay (min)", "component": "input", "inputType": "number", "min": 120, "max": 10080 },
    { "key": "reminder_3_discount_percent", "label": "Reminder 3 Discount (%)", "component": "input", "inputType": "number", "min": 0, "max": 50, "description": "Auto-generated coupon for final reminder (0 = no discount)" },
    { "key": "abandoned_cart_expiry_days", "label": "Expiry (days)", "component": "input", "inputType": "number", "min": 1, "max": 30 }
  ]
}
```

---

## Frontend

### Fe-admin
- **AbandonedCarts.vue** — list of abandoned carts with status filter
- **AbandonedCartAnalytics.vue** — dashboard widget: recovery rate, revenue recovered, funnel chart
- Nav: added to Shop section as "Abandoned Carts" item

### Fe-user
- No direct UI — recovery happens via email links that redirect to `/shop/cart`

---

## API Routes

**Admin:**
- `GET /api/v1/admin/shop/abandoned-carts` — list with filters
- `GET /api/v1/admin/shop/abandoned-carts/analytics` — recovery stats
- `POST /api/v1/admin/shop/abandoned-carts/<id>/send-reminder` — manual reminder

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | AbandonedCart model + repo | Model tests |
| 2 | AbandonedCartService — detect, remind, recover, cleanup | Service tests |
| 3 | Scheduler integration | — |
| 4 | Email templates (3 reminders) | — |
| 5 | Routes (admin) | Route tests |
| 6 | Fe-admin: abandoned cart list + analytics widget | Unit tests |
| 7 | Integration with discount system (auto coupon for reminder 3) | Integration tests |
| 8 | Config (admin-config tab) | — |
| 9 | i18n: all 8 languages | — |
| 10 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | AbandonedCartService separate from StockService and OrderService. |
| **DI** | Service injected. Email sent via core email plugin's event bus. |
| **DRY** | Reuses core scheduler pattern, email plugin pattern, discount system (06i). |
| **Clean Code** | Configurable delays. No hardcoded timeouts. |
| **No over-engineering** | Simple time-based triggers. No ML prediction of recovery likelihood. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. |
| **i18n** | All UI text + email templates in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Detection:
- test_detect_abandoned_cart_after_1h_unpaid_invoice
- test_no_detection_for_paid_invoices
- test_no_detection_for_invoices_under_1h
- test_no_detection_for_non_ecommerce_invoices

Reminders:
- test_send_reminder_1_after_configured_delay
- test_send_reminder_2_after_configured_delay
- test_send_reminder_3_with_auto_discount_coupon
- test_no_reminder_sent_twice_for_same_level
- test_reminder_email_contains_product_images_and_link

Recovery:
- test_mark_recovered_when_user_completes_purchase
- test_recovery_links_to_original_abandoned_cart

Cleanup:
- test_cleanup_expired_marks_old_carts
- test_expired_carts_not_sent_reminders

Scheduler:
- test_scheduler_job_runs_detection_and_reminders
```

## Playwright E2E

```
Admin:
- test_admin_abandoned_carts_list
    → /admin/shop/abandoned-carts → see list with status filter
- test_admin_abandoned_cart_analytics
    → see recovery rate, revenue recovered, funnel chart
- test_admin_manual_send_reminder
    → click "Send Reminder" → reminder sent → status updated

Recovery flow (requires time manipulation or short delays in test config):
- test_abandoned_cart_email_link_opens_cart_page
    → simulate email link click → /shop/cart → items still there
- test_recovered_cart_marked_in_admin
    → user completes purchase → admin sees status RECOVERED
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
# Backend (models, services, routes)
cd vbwd-backend && ./bin/pre-commit-check.sh --full

# Admin frontend (management views)
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full

# User frontend (checkout / catalog integration)
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
