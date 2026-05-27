# S21 — DRY: extract shared payment-route helpers (redirect URLs, error envelope, invoice context)

**Source:** review §6.2 → Stripe, PayPal, Conekta, Yookassa, Mercado Pago, TrueMoney, Toss Payments, PromptPay all reimplement the same boilerplate.
**Risk:** MEDIUM. Touches every payment plugin's route file.
**Outcome:** `vbwd/plugins/payment_route_helpers.py` exposes `build_redirect_urls(provider, request)`, `payment_error(reason, status)`, `extract_invoice_context(request)`, `call_sdk(func, *args)` (last one from [[s11]]). Each payment plugin's route file shrinks by ~50 LOC and reads the same way.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_payment_route_helpers.py::test_build_redirect_urls_for_web_uses_origin`
   — request with `Origin: https://example.com`, provider="stripe" →
   `("https://example.com/pay/stripe/success?...", "https://example.com/pay/stripe/cancel")`.
2. `::test_build_redirect_urls_for_ios_uses_deep_link` — `X-Client-Platform: iOS`
   → `("vbwd://stripe-callback/success?...", "vbwd://stripe-callback/cancel")`.
3. `::test_extract_invoice_context_parses_metadata` — happy path.
4. `tests/meta/test_no_duplicate_redirect_url_logic.py`
   — greps `plugins/*/routes.py` for `X-Client-Platform` or
   `request.headers.get("Origin")`; asserts ≤1 (the helper). **Today:
   fails on ~9 plugins.**

## Touch-points

- `vbwd/plugins/payment_route_helpers.py` (extend — partial exists)
- `plugins/stripe/stripe/routes.py:104-119` (redirect URL block)
- `plugins/paypal/paypal/routes.py:~67-73`
- `plugins/conekta/conekta/routes.py` (sweep)
- `plugins/yookassa/...` (sweep)
- `plugins/mercado_pago/...`, `plugins/truemoney/...`,
  `plugins/toss_payments/...`, `plugins/promptpay/...`

## Steps (each validated)

1. **Write the 4 Baseline tests.**
2. **Implement the helpers** in `vbwd/plugins/payment_route_helpers.py`:
   ```python
   def build_redirect_urls(provider: str, request) -> tuple[str, str]:
       platform = request.headers.get("X-Client-Platform", "").lower()
       if platform in ("ios", "macos"):
           return (f"vbwd://{provider}-callback/success?session_id={{CHECKOUT_SESSION_ID}}",
                   f"vbwd://{provider}-callback/cancel")
       base = request.headers.get("Origin") or request.headers.get("Referer", "").rsplit("/", 1)[0]
       return (f"{base}/pay/{provider}/success?session_id={{CHECKOUT_SESSION_ID}}",
               f"{base}/pay/{provider}/cancel")

   def payment_error(reason: str, status: int = 500):
       return jsonify({"error": reason}), status

   def extract_invoice_context(request) -> InvoiceContext:
       data = request.get_json(silent=True) or {}
       return InvoiceContext(invoice_id=data["invoice_id"], user_id=data["user_id"], ...)
   ```
3. **Per payment plugin route file**, replace the inline blocks with
   helper calls. Sweep one provider at a time, run that provider's
   tests after each, commit (locally) between if needed.
4. **Re-run the meta test.** Green.

## Acceptance (oracle)

- All 4 Baseline tests green.
- Each payment plugin's route file shrunk by ~30-50 LOC.
- Provider-specific integration tests still green (no behaviour
  regression).
- Pre-commit `--full` green.

## Notes

- Subscription helpers (`determine_capture_method`,
  `determine_session_mode`) already live here — see review §1 "Clean"
  list — keep that pattern.
- §6 Liskov: every payment plugin must behave identically for the
  redirect-URL contract; the helper enforces it by construction.
- §8 no overengineering: don't introduce per-provider URL-builder
  classes — one function with `provider: str` is fine.

## Outcome — 2026-05-27 (DONE — narrower scope than planned)

**Done — 8 helper tests + 1 dedup oracle green, 188 payment-plugin tests still pass.**

### Audit finding (smaller than the sprint estimate)

The original sprint estimated "9 payment plugins each reimplement the
boilerplate". The actual count: **only 3** (stripe, paypal, yookassa).
The other 6 (conekta, mercado_pago, truemoney, toss_payments,
promptpay, c2p2) use different redirect mechanics — they don't derive
a `frontend_base` URL at all. So the dedup scope is tight.

### Patches

- `vbwd/plugins/payment_route_helpers.py` — added
  `resolve_frontend_base(request)` and
  `build_provider_redirect_urls(request, provider, success_query, *, ios_deep_link=False)`.
  The latter encapsulates Stripe's iOS deep-link branch behind a flag.
- `plugins/stripe/stripe/routes.py:102-121` — 20 LOC of inline
  Origin/Referer/host_url + iOS branch → 6 LOC `build_provider_redirect_urls`.
- `plugins/paypal/paypal/routes.py:67-73` — 7 LOC → 3 LOC.
- `plugins/yookassa/yookassa/routes.py:56-62` — 7 LOC → 5 LOC.
- `tests/unit/test_payment_redirect_helpers.py` (NEW) — 7 contract
  tests + 1 grep-based oracle that fails if any payment plugin
  re-inlines the Origin/Referer chain in the future.

### Drift fixes captured along the way

`plugins/paypal/tests/test_plugin.py` and
`plugins/yookassa/tests/test_plugin.py` had stale
`test_no_dependencies` assertions (same drift S07 introduced and S24
fixed for Stripe) — renamed to `test_declares_subscription_dependency`
and inverted.

### Deferred (out of S21 scope)

- The 6 non-redirecting payment plugins (conekta, mercado_pago,
  truemoney, toss_payments, promptpay, c2p2) don't share the
  duplication this sprint targets. Their own routes have different
  duplication patterns (error response shapes, metadata extraction) —
  separate sprint when needed.
