# Sprint 16 — Pay with Token Balance

**Status:** Approved
**Date:** 2026-04-06
**Principles:** TDD · SOLID · DI · DRY · Core agnostic · Event-driven

---

## Decisions

| Question | Answer |
|----------|--------|
| Conversion model | Exchange rate table `vbwd_token_rate` (e.g., USDTKN = 0.05 means 1 token = $0.05) |
| Partial payment | No — all-or-nothing token payment |
| Which items | Agnostic — any invoice can be paid with tokens |
| Feature gating | Payment method disabled by default; admin enables in Settings |
| Where to show | fe-user invoice detail page, only on PENDING invoices |

---

## Data Model

### New table: `vbwd_token_rate`

```
vbwd_token_rate
├── id (UUID PK)
├── rate_name (VARCHAR 20, UNIQUE) — e.g., "USDTKN", "EURTKN"
├── rate (NUMERIC 18,8) — currency amount per 1 token (e.g., 0.05 = 1 token costs $0.05)
├── created_at, updated_at, version
```

Admin sets rates in Settings → Token Rates (permission: `settings.manage`).

### Invoice field: `tokens_total`

```
vbwd_invoice
├── tokens_total (NUMERIC 18,2, NULLABLE) — calculated on creation: brutto / token_rate
```

Calculated at invoice creation time: `tokens_total = total_amount / rate.rate`
where `rate` matches the invoice currency (e.g., `USDTKN` for USD invoices).

If no matching rate exists → `tokens_total` is NULL (token payment not available).

---

## Flow

### Invoice Creation

```
Checkout → Create Invoice
  │
  ├── total_amount = 9.99 USD
  ├── Look up vbwd_token_rate where rate_name = "USDTKN"
  │     rate = 0.05 (1 token = $0.05)
  ├── tokens_total = ceil(9.99 / 0.05) = 200 tokens
  └── Save invoice with tokens_total = 200
```

### fe-user Invoice Detail (PENDING invoice only)

```
┌─────────────────────────────────────────┐
│  Invoice #INV-20260406-123456           │
│  Status: PENDING                        │
│  Total: $9.99                           │
│                                         │
│  ─── Pay with Tokens ───────────────── │
│  Your balance:        500 tokens        │
│  Invoice token price: 200 tokens        │
│  Balance after:       300 tokens        │
│                                         │
│  [Pay with Tokens]                      │
│                                         │
│  ─── Other Payment Methods ──────────  │
│  [Pay with Stripe] [Pay by Invoice]     │
└─────────────────────────────────────────┘
```

- Button hidden if `tokens_total` is NULL (no rate configured)
- Button disabled if balance < `tokens_total`
- Not shown on PAID, CANCELLED, REFUNDED invoices

### Payment Capture

```
User clicks "Pay with Tokens"
  │
  ├── POST /api/v1/user/invoices/{id}/pay-with-tokens
  │     1. Validate invoice is PENDING
  │     2. Validate user balance >= tokens_total
  │     3. Debit tokens (TokenService.debit_tokens)
  │     4. Mark invoice PAID (payment_method = "token_balance")
  │     5. Emit PaymentCapturedEvent → triggers line item activation
  │     6. Return { invoice, new_balance }
  │
  └── 400 if insufficient balance
      402 if invoice not PENDING
```

---

## Implementation Steps

### 16a — Backend: Token Rate Model + Invoice Field

| # | What |
|---|------|
| 1 | Create `TokenRate` model in `vbwd/models/token_rate.py` |
| 2 | Add `tokens_total` column to `UserInvoice` model |
| 3 | Update all-tables migration: add `vbwd_token_rate` table + `tokens_total` column on `vbwd_invoice` |
| 4 | Create `TokenRateRepository` with `find_by_currency(currency)` |
| 5 | Update checkout handler: calculate `tokens_total` on invoice creation |
| 6 | Admin routes: CRUD for token rates (`/admin/token-rates`) with `@require_permission("settings.manage")` |
| 7 | Unit tests |

### 16b — Backend: Pay-with-Tokens Endpoint

| # | What |
|---|------|
| 1 | `POST /api/v1/user/invoices/{id}/pay-with-tokens` endpoint |
| 2 | Validate: invoice PENDING, balance >= tokens_total, tokens_total not NULL |
| 3 | Debit tokens via `TokenService.debit_tokens()` |
| 4 | Set `invoice.payment_method = "token_balance"`, mark PAID |
| 5 | Emit `PaymentCapturedEvent` (reuses existing line item activation flow) |
| 6 | Return updated invoice + new balance |
| 7 | Unit tests |

### 16c — Frontend: fe-admin Token Rate Settings

| # | What |
|---|------|
| 1 | Add "Token Rates" section to Settings → Tax tab (or new tab) |
| 2 | Table: rate_name, rate value, edit/delete |
| 3 | Inline form to create/update rates |
| 4 | i18n (8 languages) |

### 16d — Frontend: fe-user Invoice Detail

| # | What |
|---|------|
| 1 | On invoice detail page, show "Pay with Tokens" section for PENDING invoices |
| 2 | Show: current balance, token price (`tokens_total`), balance after payment |
| 3 | Button: "Pay with Tokens" → calls pay-with-tokens endpoint |
| 4 | Disable button if balance < tokens_total |
| 5 | Hide section if `tokens_total` is NULL |
| 6 | Success: refresh invoice (shows PAID), update token balance display |

### 16e — Tests + Pre-commit

| # | What |
|---|------|
| 1 | Backend unit tests: token rate CRUD, pay-with-tokens validation, debit flow |
| 2 | Playwright E2E: create rate, checkout, pay with tokens, verify balance decreased |
| 3 | `pre-commit-check.sh --full` |

---

## Permission Map

| Route | Permission |
|-------|-----------|
| `GET /admin/token-rates` | `settings.view` |
| `POST /admin/token-rates` | `settings.manage` |
| `PUT /admin/token-rates/:id` | `settings.manage` |
| `DELETE /admin/token-rates/:id` | `settings.manage` |
| `POST /user/invoices/:id/pay-with-tokens` | `@require_auth` (user's own invoice) |

---

## Not in Scope

- Token expiry
- Partial token + card payment
- Per-item token pricing
- Token gifting between users
- Token marketplace
