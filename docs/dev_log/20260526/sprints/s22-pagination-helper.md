# S22 — DRY: pagination helper for admin list routes

**Source:** review §6.3 → `vbwd/routes/admin/invoices.py`, `users.py`, `payment_methods.py` each reimplement `limit = min(int(...), 100); offset = int(...)`.
**Risk:** LOW.
**Outcome:** `vbwd/utils/pagination.py` exposes `parse_pagination_params(request, default_limit=20, max_limit=100)`. Every admin list route uses it. Magic 20/100 lifts into named constants.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_pagination.py::test_parse_returns_defaults_when_missing`.
2. `tests/unit/test_pagination.py::test_parse_clamps_to_max`.
3. `tests/unit/test_pagination.py::test_parse_rejects_negative`.
4. `tests/meta/test_no_inline_pagination.py::test_admin_routes_use_helper`
   — greps `vbwd/routes/admin/` for `request.args.get("limit"`;
   asserts ≤1 hit (the helper itself, if any test fixture). **Today: fails.**

## Touch-points

- `vbwd/utils/pagination.py` (NEW)
- `vbwd/config.py` (or `vbwd/constants.py`) — `DEFAULT_PAGE_SIZE = 20`,
  `MAX_PAGE_SIZE = 100`
- `vbwd/routes/admin/invoices.py:~39-49`
- `vbwd/routes/admin/users.py`
- `vbwd/routes/admin/payment_methods.py`
- Any plugin admin route doing the same — `rg "request.args.get\(\"limit\"" plugins/`

## Steps (each validated)

1. **Write the 4 Baseline tests.**
2. **Implement the helper:**
   ```python
   def parse_pagination_params(request, default_limit=DEFAULT_PAGE_SIZE, max_limit=MAX_PAGE_SIZE):
       try:
           limit = min(max(int(request.args.get("limit", default_limit)), 1), max_limit)
           offset = max(int(request.args.get("offset", 0)), 0)
       except (TypeError, ValueError):
           raise BadRequest("limit and offset must be integers")
       return limit, offset
   ```
3. **Replace inline parsing** in each admin route.
4. **Re-run all admin-list integration tests** — green.

## Acceptance (oracle)

- All 4 Baseline tests green.
- Meta test green.
- Pre-commit `--full` green.

## Notes

- Tiny sprint but high signal — sets the precedent that boilerplate
  goes into `vbwd/utils/`, not inlined per route.
- §8 no overengineering: don't introduce cursor-based pagination yet
  — limit/offset is what the API contract says today.
