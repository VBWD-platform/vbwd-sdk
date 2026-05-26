# S24 — Narrow bare excepts; lift magic numbers into named constants

**Source:** review §7.2 + §7.3.
**Risk:** LOW. Pure clean-code refactor with characterisation tests.
**Outcome:** Every `except Exception:` either (a) names the specific exception type or (b) logs at the right level before swallowing. Every numeric/string literal repeated more than twice or carrying domain meaning is a named constant.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/meta/test_no_bare_except_exception.py::test_no_unlogged_broad_except`
   — parses `vbwd/` + `plugins/` for `ExceptHandler(type=Name('Exception'))`;
   asserts the body either calls `logger.{warning,error,exception}` or
   re-raises. **Today: fails on at least 3 sites.**
2. `tests/meta/test_no_magic_currency_multiplier.py`
   — greps `* 100` next to `unit_price` / `amount` patterns; asserts
   only `STRIPE_CURRENCY_MULTIPLIER` (or equivalent named constant).
   **Today: fails.**

## Touch-points (from review)

Excepts:
- `vbwd/plugins/config_schema.py:62-63`
- `vbwd/models/invoice_line_item.py:56-57`
- `vbwd/routes/admin/users.py:107-108`
- Sweep `rg "except Exception:" vbwd/ plugins/`

Magic numbers:
- `plugins/stripe/stripe/routes.py:74` → `int(line_item.unit_price * 100)` → `STRIPE_CURRENCY_MULTIPLIER = 100`
- `vbwd/routes/admin/payment_methods.py` → `limit = min(int(...), 100)` → covered by [[s22]]
- `vbwd/utils/transaction.py:26` → implicit timeout

## Steps (each validated)

### Part A — excepts

1. **Write the meta test.** Red.
2. **For each hit**, decide:
   - If the exception is expected (e.g. file-not-found in config
     loader), catch the specific class (`FileNotFoundError`) and log
     at `debug`.
   - If unexpected but recoverable (e.g. optional event dispatcher
     missing), catch `Exception as exc` and `logger.warning(...)` with
     `exc_info=True`.
   - If unexpected and not recoverable, **don't catch** — let it
     propagate to the global error handler.
3. Re-run meta test — green.

### Part B — magic numbers

4. **Write the meta test.** Red.
5. **For each plugin / service with magic numbers** carrying domain
   meaning, add to a `constants.py` file in the closest module:
   - `STRIPE_CURRENCY_MULTIPLIER = 100` in `plugins/stripe/stripe/constants.py`
   - `DEFAULT_PAGE_SIZE = 20`, `MAX_PAGE_SIZE = 100` in `vbwd/constants.py`
     (already added by [[s22]])
   - `DB_TRANSACTION_TIMEOUT_SECONDS = 30` in `vbwd/constants.py`
6. Replace inline uses; re-run meta test — green.

## Acceptance (oracle)

- Both meta tests green.
- `rg "except Exception:" vbwd/ plugins/` shows only sites where a
  log call is on the next 1-2 lines.
- `rg "\\* 100" plugins/stripe/` shows only the constant declaration.
- Pre-commit `--full` green.

## Notes

- §6 Liskov: silent excepts are LSP-killers — subclasses can hide
  real bugs behind a 200 OK response. This sprint closes that gap.
- §8 no overengineering: don't introduce a unified error-handling
  middleware here (that's a separate concern); just stop swallowing.
