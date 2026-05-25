# S10 — Pay an invoice with token balance (as a payment plugin)

**Status:** PLANNED — 2026-05-25. Revives & re-architects the approved-but-never-built
[`../../20260403/sprints/16-token-payment.md`](../../20260403/sprints/16-token-payment.md)
(2026-04-06) for the **current** post-subscription-extraction architecture.
**Track:** independent — not a Sprint-11 sub-sprint. `s10` to avoid the reserved
`S8`/used `s9` in this folder.
**Repos (SDK dirs now, own repos on extraction):** `vbwd-backend/plugins/token-payment/`
→ `vbwd-plugin-token-payment`; `vbwd-fe-user/plugins/token-payment/` →
`vbwd-fe-user-plugin-token-payment`. **No core changes** (see §1).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **core agnostic** · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate:
`bin/pre-commit-check.sh --full` green per touched repo.

---

## 0. Decision — core or module? → **MODULE (plugin).**

Pay-with-tokens is a **payment method**, and in this codebase *every* payment
method is a plugin that extends `PaymentProviderPlugin`
(`vbwd-backend/vbwd/plugins/payment_provider.py:40`) — stripe, paypal, yookassa,
conekta, etc. So:

- **It is a plugin, not core.** Core stays agnostic — it must not learn a specific
  method's business logic (token↔currency rate, all-or-nothing). (Project law:
  *"vbwd core is agnostic — only plugins are gnostic."*)
- **The token wallet is already core** and stays there — `TokenService`
  (`vbwd/services/token_service.py`: `get_balance:29`, `debit_tokens:80`,
  `credit_tokens:38`) and the `UserTokenBalance`/`TokenTransaction` models. That
  is generic, agnostic infra (a wallet), reused by the chat plugin
  (`plugins/chat/src/chat_service.py:51` debits `USAGE`) and by meinchat token
  transfer (item **d**). The new plugin **reuses** it via DI — no new wallet.
- **Shipping:** bundle it in the **default install recipe** as a standard plugin,
  **disabled by default** (admin enables it) — "shipped with the distribution,
  not baked into agnostic core." That satisfies the original "disabled by default,
  admin enables" gate via the normal plugin enable/disable model.

So: a default-bundled, off-by-default **plugin**; the wallet it spends from is core.

## 1. What changed vs the 2026-04-06 design (now agnostic)

The old design coupled core to this one feature. We drop that:

| 2026-04-06 (rejected) | Now (agnostic) |
|---|---|
| `tokens_total` column on **core** `vbwd_invoice` | **No core column.** Token cost computed on demand: `ceil(total_amount / rate)`. Core invoice stays money-only (`invoice.py` — confirmed no `tokens_total`). |
| `vbwd_token_rate` table in **core** `vbwd/models/` | Rate lives in the **plugin** (config map `currency → rate_per_token` in `admin-config.json`; a plugin-owned table only if dynamic CRUD is later needed). |
| Endpoint in core/subscription routes | Endpoint in the **plugin** blueprint: `POST /api/v1/plugins/token-payment/invoices/<id>/pay`. |
| New `PAYMENT` enum value (core change) | **Reuse `TokenTransactionType.USAGE`** (`enums.py:109`) with `reference_id=invoice_id` — zero core enum change. |
| Admin "Token Rates" in core Settings | Rate config via the **plugin's** admin-config (gated `settings.manage`). |

## 2. Seams to reuse (all already exist)

- **Read/spend balance:** `TokenService.get_balance(user_id)` / `debit_tokens(user_id, amount, type, reference_id, description)` (raises on insufficient) / `credit_tokens(...)` for refunds.
- **Finalize payment (no external gateway):** `emit_payment_captured(invoice_id, payment_reference, amount, currency, provider)` (`vbwd/plugins/payment_route_helpers.py:72`) → `PaymentCapturedEvent` → `PaymentCapturedHandler` (`vbwd/handlers/payment_handler.py`) marks invoice **PAID** and runs the **line-item registry** (`vbwd/events/line_item_registry.py`) so subscriptions activate / token bundles credit — exactly like every other payment plugin.
- **Validate:** `validate_invoice_for_payment(invoice_id, user_id)` (`payment_route_helpers.py:38`).
- **Payment-method record:** `vbwd_payment_method` (code/plugin_id/is_active/currencies/config) via admin or the plugin's seed.

## 3. Design

### Backend plugin `token-payment` (`PaymentProviderPlugin`)

- Registers payment method `code="token-balance"`, `plugin_id="token-payment"`, off by default.
- **Pay route** `POST /api/v1/plugins/token-payment/invoices/<id>/pay` (`@require_auth`, own invoice):
  1. `validate_invoice_for_payment(id, user)` → must be PENDING/payable.
  2. Resolve `rate = config.rates[invoice.currency]`; if none → **402 method unavailable** (button is hidden client-side too).
  3. `tokens_needed = ceil(invoice.total_amount / rate)`.
  4. `TokenService.debit_tokens(user, tokens_needed, USAGE, reference_id=invoice.id, description="Invoice <num>")` — **atomic**; raises → **400 insufficient balance**.
  5. `emit_payment_captured(invoice.id, payment_reference=f"token-balance:{txn_id}", amount=total_amount, currency, provider="token-payment")`.
  6. Return `{ invoice, tokens_spent, new_balance }`.
- **Quote route** `GET /api/v1/plugins/token-payment/invoices/<id>/quote` → `{ available: bool, tokens_needed, balance, balance_after }` so the UI never duplicates the rate math (DRY — one home for the conversion).
- **Refund:** `refund_payment()` → `credit_tokens(REFUND, reference_id=invoice.id)`. (Stretch; wire to the refund path other plugins use.)
- `PaymentProviderPlugin` methods that assume an external gateway (`verify_webhook`/`handle_webhook`) are **no-ops** here — internal synchronous payment. (Liskov: the no-op honours the base contract; callers that branch on "has webhook" must not break — assert in tests.)

### fe-user plugin `token-payment`

- A **"Pay with tokens"** panel on a **PENDING** invoice: shows balance, token cost, balance-after; button calls the pay route; on success re-fetches the invoice (PAID) and the balance.
- Hidden when the quote says `available=false` (no rate for currency); disabled when `balance < tokens_needed`.
- **Agnostic UI seam:** contribute via a generic `invoicePaymentMethods` extension registry in fe-user core (mirror of fe-admin's `invoiceDetailSections` from S6) — the plugin registers a component; core `InvoiceDetail.vue`/`InvoicePay.vue` render registered methods instead of today's hard-coded stripe/paypal buttons. *(One small, generic, agnostic core seam — the only fe-user-core touch; verify if a payment-method extension point already exists before adding.)*
- Balance read reuses the existing tokens store/endpoint the tokens page uses.

### SOLID / DI / Liskov

- **S:** plugin = the token-payment method; conversion in one quote service; core wallet untouched.
- **O:** new method via the payment-plugin + the `invoicePaymentMethods` registry — no core `if method == …`.
- **L:** internal-payment plugin substitutes for any `PaymentProviderPlugin` (no-op webhook path safe).
- **D/DI:** plugin depends on the core `TokenService` + `emit_payment_captured` ports, never the reverse.
- **DRY:** rate math lives only in the plugin (quote endpoint), consumed by the UI.

## 4. TDD plan (RED first)

Backend (plugin `tests/`, MagicMock repos / fake `TokenService`):
- quote: rate present → tokens_needed=ceil(total/rate), balance_after; no rate → `available:false`.
- pay: PENDING + sufficient balance → debits once (USAGE, reference_id=invoice), emits `PaymentCapturedEvent`, returns new balance; **integration** asserts invoice → PAID + line items activated.
- pay: insufficient balance → 400, **no** debit, **no** capture (atomic, no partial spend).
- pay: non-PENDING / already paid → 402, no debit (idempotent).
- refund → credit_tokens(REFUND).
- Liskov: webhook no-ops don't break the provider contract.

fe-user (vitest): panel hidden when `available:false`; disabled when balance<cost; click → pay → invoice PAID + balance updated. E2E (playwright): configure a rate, checkout to a PENDING invoice, pay with tokens, assert balance decreased and invoice PAID.

## 5. Files / repos

- Backend: `vbwd-backend/plugins/token-payment/` — `__init__.py` (plugin), `token_payment/{routes.py,service.py}`, `config.json` + `admin-config.json` (rates map + `debug_mode`), `tests/`. (No migration if rates live in config.)
- fe-user: `vbwd-fe-user/plugins/token-payment/` — payment-method component + registration; (+ generic `invoicePaymentMethods` registry in fe-user core if absent).
- Register in `plugins/plugins.json` (enabled:false) + `plugins/config.json`.
- Extract to standalone repos per the plugins-in-own-repos rule.

## 6. Acceptance criteria

- With the plugin **enabled** and a rate set for the invoice currency: a PENDING invoice shows "Pay with tokens"; paying debits the wallet once, marks the invoice PAID, and activates its line items (subscription/token-bundle) via the shared capture path.
- **Disabled / no rate** → method absent everywhere; core invoice flow unchanged.
- Insufficient balance → clear 400, no debit, no capture. All-or-nothing.
- **Core untouched** except the one generic `invoicePaymentMethods` UI seam: no `tokens_total` on core invoice, no token-rate table in core, no `PAYMENT` enum, no token-method code in core routes. Agnosticism oracle stays green.
- Gate green on each repo.

## 7. Out of scope

Partial token+card, per-item token pricing, token expiry, dynamic multi-rate CRUD
table (config map suffices now), FX between token rates. (Token transfer between
users — item **d** — already exists in meinchat; out of scope here, but shares the
same core wallet.)
