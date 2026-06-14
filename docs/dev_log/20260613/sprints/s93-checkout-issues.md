# S93 — Checkout issues

**Area:** `vbwd-fe-user` (public + dashboard checkout, booking checkout) · `vbwd-backend` (public config endpoint) · possibly `vbwd-fe-core`. **Engineering requirements:** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — BINDING per [`_engineering_requirements.md`](_engineering_requirements.md). Guard: `bin/pre-commit-check.sh --full` green on every touched repo. **Not committed** without explicit instruction.

---

## Slice A — currency on checkout (THIS slice)

The single operating currency is the **global default currency** (`default_currency` core setting, S84 — currently `EUR`). Checkout must use it **everywhere**; never `'USD'`, never `undefined`, never a per-item/converted currency.

### A1 — Public checkout shows different currencies / wrong total
`/checkout?tarif_plan_id=pro` (`plugins/checkout/PublicCheckoutView.vue`): the Order-Summary breakdown renders the plan correctly in **€** (Net €29.99 / VAT €5.70 / Gross €35.69), but the bottom **"Total: $50.69"** is in `$` AND a different value.
- Root cause 1 (currency): `vue/src/stores/checkout.ts:49` → `currency = lineItems[0]?.currency || 'USD'` falls back to **USD**; `PublicCheckoutView.vue:117` / `:144` / `:228` also `|| 'USD'`. → `$`.
- Root cause 2 (value): `orderTotal` (`checkout.ts:45` = `activeSource.getOrderTotal()`) returns **50.69**, not the plan gross **35.69** — the subscription `CheckoutSource.getOrderTotal()` is inconsistent with the breakdown gross (mixes net/gross or includes an extra amount). Must equal the displayed gross in the default currency.

### A2 — Booking checkout: "Pay Now 189.00 undefined"
`plugins/booking/booking/views/BookingCheckout.vue` reads `resource.currency` (lines ~64, ~125, ~194) — but S85.1 **dropped `currency`** from `booking_resource`, so it renders `undefined`; the total/price also lack a currency symbol and aren't `formatMoney`-formatted.

### Fix (A)
- **Expose the global default currency to the fe**: add `default_currency` (and `prices_display_mode`, `prices_mode_in_db`) to the **public config endpoint** `vbwd/routes/config.py` (today it only serves languages). One read = the fe's single source of truth for the operating currency + display mode.
- **fe single source of truth**: a small config store/composable reads it once; checkout uses it as the universal currency — replace every `|| 'USD'` and every dropped-`resource.currency`/`undefined` with the global default.
- `PublicCheckoutView`: Total + Pay button use the default currency via `formatMoney`; `orderTotal` must equal the breakdown gross (fix the subscription `getOrderTotal()` so the Total matches the Gross line; investigate the +€15 discrepancy).
- `BookingCheckout`: replace `resource.currency` with the global default; format all amounts (line, total, Pay button) via `formatMoney` — no "undefined".
- Tests: checkout currency getter returns the global default (never USD) when line items lack a currency; Total == breakdown gross in the default currency; booking Pay button shows "<default-symbol> 189.00" (no "undefined"); a guard that no checkout surface hardcodes `'USD'` or reads `resource.currency`.

---

## Slice B — token payment regressions (looks like a rollback; SEPARATE follow-up)
1. **"Token balance before/after" block disappeared** from "Pay with tokens".
2. **Token payment is an instant charge** — tokens must be **transferred to the configured "Token manager" user** (set at `/admin/settings/backend-plugins/token_payment`), not merely decremented from the payer.
3. **Pay-invoice-with-tokens disappeared** from the user dashboard.

These three predate Slice A and read as a regression/rollback of earlier token-payment work — scope + fix separately after Slice A.
