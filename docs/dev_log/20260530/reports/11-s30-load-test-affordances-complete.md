# Report 11 — S30: backend code affordances for robust load testing

**Date:** 2026-06-02
**Status:** ✅ **DONE & GREEN.** Three additive, debug-gated affordances ship so
load-test harness drift surfaces at *boot* (a URL typo) and silent partial seed
becomes impossible. Core stays agnostic. **Not committed** (standing rule).

## What shipped (3 slices, TDD-first)

**Slice 0 — `flask seed [PLUGIN]... [--strict/--best-effort] [--json] [--reset]`**
(`vbwd/cli/seed.py`): discovers enabled plugins via `current_app.plugin_manager`
(NOT the filesystem, NOT a plugin import), calls each plugin's optional
`populate()` and otherwise falls back to `runpy`-running its `populate_db.py`
**with exit-code propagation** (today's seed loop swallows failures with
`|| true`). Writes a success marker. Strict = fail on first error (exit 1);
best-effort = continue + report; unknown plugin = exit 2; disabled plugins
skipped.

**Slice 1 — `GET /api/v1/_routes`** (`vbwd/routes/debug/routes_catalog.py`):
lists every registered route `{method, path, endpoint, auth_required,
permission}`. The S29 Locust pre-load smoke reads this to fail fast on URL drift.

**Slice 2 — `GET /api/v1/_seed_status`** (`vbwd/routes/debug/seed_status.py`):
`{seeded, unseeded, populated_at}` from a new core table
`vbwd_plugin_seed_marker(plugin_name PK, populated_at)`. The harness asserts
`unseeded == []` after seeding.

**Shared debug gate** (`vbwd/middleware/debug.py::require_debug_enabled`): both
endpoints 404 unless `ENABLE_DEBUG_ENDPOINTS is True` (read at request time so
fixtures flip it). Default off (prod-safe); CI/dev opt in via
`VBWD_ENABLE_DEBUG_ENDPOINTS=1` (documented in `.env.example`). The debug
blueprint is CSRF-exempt.

Also: `vbwd/middleware/auth.py` now stamps `requires_auth` / `required_permission`
markers on its decorator wrappers so the route catalog reports auth/permission
without source-parsing.

## Files

- **Added:** `vbwd/cli/seed.py`, `vbwd/middleware/debug.py`,
  `vbwd/routes/debug/{__init__,routes_catalog,seed_status}.py`,
  `vbwd/models/plugin_seed_marker.py`, `vbwd/repositories/seed_marker_repository.py`,
  `alembic/versions/20260602_1000_seed_marker.py`.
- **Changed:** `vbwd/app.py` (register `seed_command` + debug bp + default flag),
  `vbwd/cli/__init__.py`, `vbwd/models/__init__.py`, `vbwd/middleware/auth.py`,
  `.env.example`.
- **Tests:** `tests/unit/cli/test_seed_command.py` (11),
  `tests/unit/routes/debug/test_routes_catalog.py` (6),
  `tests/unit/routes/debug/test_seed_status.py` (4),
  `tests/unit/middleware/test_require_debug_enabled.py` (4),
  `tests/integration/test_seed_full_loop.py` (1) — **26 specs**, exceeds the ≥20 plan.

## Migration (graph-safe)

`20260602_1000_seed_marker` (revision id 25 chars), `down_revision =
"20260526_2200_md_jsonb"` — the current **core** head, no plugin revision
involved. Independently verified: it appears as a head, is in `alembic history`,
and `alembic heads` still resolves (10 heads — the pre-existing fragmented
design, not introduced here). Integration loop test (`flask seed` → marker
written → `/_seed_status` reflects it) passes.

## Gate (`bin/pre-commit-check.sh`)

- `--quick` → **PASS** (black, flake8 `--max-line-length=120`, mypy; unit **2468
  passed / 5 skipped**). Integration loop test run directly (passed) as the only
  integration touchpoint.
- **Independently re-verified by me:** 26 new specs + the core-agnosticism oracle
  (`tests/unit/test_core_agnosticism.py`) → 26 passed; black + flake8 clean on all
  touched files; migration head/history/up-loop confirmed; all S30 files untracked
  (no commit).
- End-to-end smoke: `flask seed all --json` discovers all 23 enabled plugins;
  endpoints 404 when off, 200 with ~469 routes when on.

## Deviations from the sprint doc (all defensible, contract unchanged)

1. **Plugin source = real API.** Doc samples show `container.plugin_manager()` /
   `list_enabled()`; the platform exposes `current_app.plugin_manager` /
   `get_enabled_plugins()` (matches `vbwd/routes/admin/plugins.py`). Used the real one.
2. **No-seed-source = no-op success.** A plugin with neither `populate()` nor
   `populate_db.py` is a seeded no-op (marker written, `ok=True`), not an error —
   otherwise `seed all --strict` could never pass (many plugins ship no demo
   data). A `populate_db.py` exiting non-zero is still a hard error. Guarded by a spec.
3. **`--reset`** is a flag on `seed` (`flask seed <name> --reset`), per Slice 2.

## Follow-up observed (out of S30 scope)

Live `flask seed all` surfaced meinchat's own `populate()` raising `'alice' is
already taken` on an already-seeded DB — a **meinchat idempotency** bug, not S30.
The CLI correctly surfaces it (which is the point). Worth a small meinchat
follow-up to make its seed idempotent.

## Coordination with S29

S29 §3.0 seed step → `docker compose exec -T api flask seed all` +
`curl /_seed_status` asserting `unseeded == []`. S29 §3.2 smoke → real
`GET /_routes` instead of the `if hasattr(...)` no-op. Both now unblocked.
