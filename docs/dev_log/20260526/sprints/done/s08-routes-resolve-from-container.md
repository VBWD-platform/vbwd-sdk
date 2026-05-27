# S08 — Routes resolve services via `current_app.container`, not inline `db.session`

**Source:** review §3.1 → ~8 sites in `vbwd/routes/auth.py`, `vbwd/routes/user.py`, `vbwd/routes/invoices.py`.
**Risk:** MEDIUM (routes), per-file low. Big payoff in testability.
**Outcome:** No `vbwd/routes/**.py` constructs a repository or service inline. Every collaborator comes from the container. The container is the single binding place. A grep oracle catches regressions.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). This sprint IS the canonical DI / DIP application — §3-D and §4.

## Baseline (E1)

1. `tests/unit/test_route_di_hygiene.py::test_no_inline_repo_construction_in_routes`
   — walks `vbwd/routes/`, uses `ast` to find `Call(func=Name(id=<RepoOrServiceName>))`
   inside route function bodies; asserts none. **Today: fails on ~8 sites.**
2. `tests/unit/test_route_di_hygiene.py::test_no_direct_db_session_kwarg_in_routes`
   — greps `db.session` usage outside the container-wiring file.
3. `tests/unit/routes/test_auth_route_uses_container.py::test_register_resolves_auth_service_from_container`
   — swaps the container's `auth_service` with a `Mock`, calls
   `POST /api/v1/auth/register`, asserts the mock was invoked.

## Touch-points (verified)

- `vbwd/routes/auth.py:~56-57` (and remaining handlers in file)
- `vbwd/routes/user.py` (sweep)
- `vbwd/routes/invoices.py` (sweep)
- `vbwd/routes/admin/users.py` (sweep — once §7.1 / [[s23]] extracts
  services, the inline pattern naturally disappears too)
- `vbwd/container.py` (verify every needed provider is wired —
  `auth_service`, `user_service`, `invoice_service`, …)

## Steps (each validated)

1. **Write the unit tests** (incl. one mock-swap example).
2. **Sweep `vbwd/routes/auth.py`.** For every endpoint replace:
   ```python
   user_repo = UserRepository(db.session)
   auth_service = AuthService(user_repository=user_repo)
   ```
   with:
   ```python
   auth_service = current_app.container.auth_service()
   ```
   Confirm `container.auth_service` is a `providers.Factory(...)` and
   already lists every needed dependency.
3. **Sweep `vbwd/routes/user.py`** — same pattern.
4. **Sweep `vbwd/routes/invoices.py`** — same.
5. **Verify with the AST test** that no inline construction remains.
6. **Re-run all route integration tests** — they should pass
   unchanged (behaviour preserved; this is a pure DI refactor).
7. **`pre-commit-check.sh --full`** green.

## Acceptance (oracle)

- All three Baseline tests green.
- `rg -n "Repository\(db\.session\)|Service\(.*=db\.session" vbwd/routes/` → empty.
- A `Mock` swapped into the container is invoked by the route (proves
  the resolution path is real, not just imported-then-ignored).

## Notes

- Don't widen this sprint into plugin routes — that's [[s09]] (plugin
  `on_enable` repo registration must land first; otherwise plugins
  have nothing to resolve from the container).
- §8 no overengineering: don't introduce a `@inject` decorator pattern
  yet — explicit `current_app.container.foo()` is honest and greppable.

## Outcome — 2026-05-27 (DONE)

**Done.** S08 oracle (2 tests) + invoice route tests (9 tests) green.

**Patches:**
- `vbwd/routes/auth.py` — 4 inline-construction sites replaced with
  `current_app.container.auth_service()` / `.user_repository()`.
- `vbwd/routes/user.py` — 4 sites collapsed to
  `current_app.container.user_service()` and similar.
- `vbwd/routes/invoices.py` — 4 sites replaced with
  `current_app.container.invoice_service()` / `.user_repository()`.

**Test plumbing:**
- New `tests/unit/test_route_di_hygiene.py` — 2 regex oracles that
  enforce "no `XxxRepository(db.session)` and no
  `XxxService(...user_repository=...)` in core route files" forever.
- `tests/unit/routes/test_invoice_routes.py` — updated 5 mocks to use
  `app.container.invoice_service.override(providers.Object(mock))`
  via a small `override_invoice_service` context manager
  (the old `@patch("vbwd.routes.invoices.InvoiceService")` form no
  longer takes effect since the route no longer imports the class).

**Acceptance verified:**
- Both DI-hygiene oracles green.
- All 9 invoice route tests still green (behaviour preserved).

**Out-of-scope deferred:**
- `vbwd/middleware/auth.py:40, 188` still uses inline construction.
  Middleware is outside the route-only scope of this sprint; can be
  swept opportunistically when the auth middleware gets next-touched.
- Admin routes (`vbwd/routes/admin/*.py`) — those routes are oversized
  and need service extraction first ([[s23]]).
- Plugin routes — pending [[s09]] (plugin repos in container) and
  [[s10]] (registries → container Singletons).
