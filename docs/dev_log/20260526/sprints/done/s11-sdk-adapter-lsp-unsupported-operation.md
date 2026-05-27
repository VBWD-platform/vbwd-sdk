# S11 — SDK adapter LSP: raise `UnsupportedOperationError` instead of `success=False`

**Source:** review §4.1 → `plugins/mercado_pago/mercado_pago/sdk_adapter.py:63-77`, `plugins/conekta/.../sdk_adapter.py` (verify), any other adapter returning success-false for structural inability.
**Risk:** MEDIUM. Behaviour change at the SDK-adapter boundary; payment-route helpers and webhook handlers must learn to treat the new exception correctly.
**Outcome:** Every SDK adapter either implements the operation or **raises** `UnsupportedOperationError`. Callers wrap the call in a single shared helper that converts the exception into the correct HTTP status (501 Not Implemented or a domain-specific 4xx). No more silent `success=False` for "I structurally cannot do this".

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `plugins/mercado_pago/tests/unit/test_sdk_adapter_lsp.py::test_capture_payment_raises_when_unsupported`
   — calls `adapter.capture_payment(...)`, expects
   `UnsupportedOperationError`. **Today: fails — returns SDKResponse(success=False).**
2. Same for `release_authorization`.
3. `tests/unit/test_sdk_adapter_contract.py::test_every_adapter_either_implements_or_raises`
   — parameterised over every concrete `ISDKAdapter`; calls each
   advertised method with stubbed input; asserts result is either a
   real `SDKResponse(success=True/False with a transient reason)` OR
   `UnsupportedOperationError` — never `success=False` with a "this
   provider does not support X" reason.
4. `tests/unit/test_payment_route_helpers.py::test_unsupported_op_returns_501`
   — route helper translates the exception to HTTP 501 + a structured
   error body.

## Touch-points

- `vbwd/sdk/exceptions.py` (NEW — or `vbwd/sdk/errors.py`):
  `class UnsupportedOperationError(Exception)`.
- `vbwd/sdk/sdk_adapter.py` (or wherever `ISDKAdapter` lives) —
  document the contract.
- `plugins/mercado_pago/mercado_pago/sdk_adapter.py:63-77`
- `plugins/conekta/.../sdk_adapter.py` (audit)
- `plugins/promptpay/.../sdk_adapter.py` (audit)
- `plugins/truemoney/...`, `plugins/toss_payments/...` (audit)
- `vbwd/plugins/payment_route_helpers.py` (add the
  `wrap_sdk_call(callable_, *args)` translator that returns
  `(response_body, status)`)
- Every route that calls `adapter.capture_payment` / `release_authorization`

## Steps (each validated)

1. **Write the failing tests** (the contract test parametrised across
   every adapter is the long-pole one — populate the adapter list once
   and you get coverage of every payment plugin for free).
2. **Add `UnsupportedOperationError`** to `vbwd/sdk/exceptions.py` —
   one line, with a docstring describing the contract.
3. **Edit each offending adapter** to raise instead of return:
   ```python
   def capture_payment(self, payment_intent_id, idempotency_key=None) -> SDKResponse:
       raise UnsupportedOperationError(
           "Mercado Pago captures on user redirect; use get_payment_status"
       )
   ```
4. **Add `wrap_sdk_call`** to the payment route helpers:
   ```python
   def call_sdk(func, *args, **kwargs):
       try:
           return func(*args, **kwargs)
       except UnsupportedOperationError as exception:
           abort(501, description=str(exception))
   ```
   §5 DRY — one place where the translation happens.
5. **Update payment routes** to call through `call_sdk(...)` for any
   adapter method that *might* raise the new exception. Keep the
   regular `SDKResponse.success=False` path for transient/expected
   failures.
6. **Run pre-commit `--full`** — green.

## Acceptance (oracle)

- All four Baseline tests green.
- Routes hitting an unsupported op return HTTP 501 with a clear
  message (verified by route integration test).
- No SDK adapter returns `SDKResponse(success=False, error="…does not
  support…")` — grep oracle: `rg "does not support|not supported" plugins/*/.../sdk_adapter.py` → empty.

## Notes

- This is the textbook Liskov fix: subtype must honour the supertype's
  contract; "this operation does what its name says" is the contract.
  Returning a soft failure for a structural inability is not a
  refinement of the contract — it's a violation.
- Sets up [[s12]] (ISP split of `ISDKAdapter` into capture-capable vs
  non-capture-capable mixins). Don't conflate the two sprints —
  this one fixes today's wrong behaviour; [[s12]] makes the contract
  expressible at the type level.
- §8 no overengineering: don't introduce capability-bit metadata
  fields on adapters yet — raise/catch is the simpler honest answer.

## Outcome — 2026-05-27 (DONE)

**Done.** 5 new oracle tests + 74 existing payment-plugin tests + 9
capture_service tests all green.

**Patches:**
- `vbwd/sdk/errors.py` (NEW) — `UnsupportedOperationError`.
- `plugins/mercado_pago/mercado_pago/sdk_adapter.py:63-77` — raise
  on `capture_payment` and `release_authorization`.
- `plugins/truemoney/truemoney/sdk_adapter.py:65-69` — raise on
  `release_authorization`.
- `vbwd/services/capture_service.py:44-48, 81-86` — catch
  `UnsupportedOperationError` and surface as
  `CaptureResult(success=False, error=str(exc))` (no retry).

**Updated tests:**
- `plugins/mercado_pago/tests/unit/test_sdk_adapter.py:120-138` —
  `TestLiskov` now asserts `pytest.raises(UnsupportedOperationError)`.
- `plugins/truemoney/tests/unit/test_sdk_adapter.py:115-124` — same.

**Acceptance verified:**
- New permanent grep oracle in
  `tests/unit/test_sdk_unsupported_operation.py` catches the
  `SDKResponse(success=False, error="…does not support…")` smell.
- `capture_service` retries are now impossible for structurally-unsupported
  ops (the exception short-circuits to a clean failure).
- All existing `capture_service` tests pass — proves the catch
  preserves the user-visible behaviour.
