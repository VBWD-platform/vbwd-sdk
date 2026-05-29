# S30 — Backend code affordances for robust load testing

**Status:** PLANNED — 2026-05-28
**Triggered by:** [Run #26452905684 — harness drift](../reports/04-heavy-load-26452905684-harness-drift.md)
+ the recognition that the same harness pain (contract drift, silent
partial seed) will recur every time the API changes shape unless the
backend exposes affordances for the harness to lean on.
**Repo:** `vbwd-backend` (core `vbwd/` + each affected plugin's `populate_db.py`).
**Track:** independent of [S29](s30-heavy-load-harness-fixes.md) but
*co-operative* — when both ship, S29 §2.1 / §3.2 become one-liners
instead of bespoke shell + Python.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** (the introspection endpoints are core; the populate-CLI is core+plugin) · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --full` GREEN on `vbwd-backend`; new endpoints reachable in dev (`docker compose exec api flask seed all`, `curl /api/v1/_routes`, `curl /api/v1/_seed_status`).

---

## 1. Goal

Make load-test harness fragility a one-time cost, not a recurring one.
After this sprint, harness drift surfaces at *boot* (a contract
introspection endpoint catches a URL typo) and silent partial seed
becomes impossible (a single CLI orchestrates every plugin's idempotent
seed function with proper exit codes).

Three small additions:

1. **`flask seed [plugin|all]`** — a core CLI that discovers every
   enabled plugin's idempotent seed function and runs them inside the
   api container with deterministic ordering + a non-zero exit code on
   any failure. Replaces ad-hoc `python plugins/<name>/populate_db.py`
   loops.
2. **`GET /api/v1/_routes`** — debug-only introspection endpoint
   listing every registered route with its method, path template, and
   auth requirement. The Locust scenario's pre-load smoke (S29 §3.2)
   reads this to fail-fast on URL drift.
3. **`GET /api/v1/_seed_status`** — debug-only endpoint exposing
   `{seeded_plugins: [...], unseeded_plugins: [...], populated_at: {...}}`.
   The harness asserts `unseeded_plugins == []` after the seed step;
   no more silent partial seeds.

Each is debug-gated (off in production unless explicitly enabled), so
this sprint has zero attack surface in prod.

## 2. Why these three, not the full OpenAPI rabbit hole

Considered & rejected for this slice (kept for the
"out of scope" list, §7):

| Option | Why deferred |
|---|---|
| **Full OpenAPI emission** (`apispec` + `marshmallow-jsonschema` or `pydantic-openapi`) | Cost: weeks. Benefit for harness: marginal — we need "is this URL registered?", not "what's the JSON schema of the body?". Full OpenAPI is a *product* feature for SDK generation, not a *test-hygiene* feature. |
| **Loadtest fixture per plugin** (auto-pool of N users / N invoices / N tarif-plans) | Useful but solvable by the harness side seeding the standard demo data via this sprint's `flask seed all` + then drawing from the existing demo users (`test@example.com` etc.). |
| **API versioning / contract test framework** (`schemathesis`, `dredd`) | Same scope concern. The `_routes` endpoint covers 90 % of harness needs at 5 % of the cost. |
| **Switching `populate_db.py` to a `requests`-only client** (no `vbwd.*` import) | Awkward — populate scripts genuinely *do* want SQLAlchemy semantics (transactional bulk insert, idempotent upsert via repo). The right answer is "run them in the container", not "rewrite them to call the API." |

NO OVERENGINEERING: ship the minimum that makes harness drift
loud, defer everything else until a concrete need surfaces.

---

## 3. Slices

### Slice 0 — `flask seed` CLI

**Files added:**
- `vbwd-backend/vbwd/cli/seed.py` (~80 LOC).

**Files touched:**
- `vbwd-backend/vbwd/cli/__init__.py` — register the new command group.
- Each plugin's `__init__.py` — optionally exposes a `populate()`
  method on the plugin class that the CLI calls (default: shells to
  the existing `populate_db.py` for backward compat). New convention,
  not a forced migration.

**Contract:**

```bash
$ docker compose exec api flask seed --help
Usage: flask seed [OPTIONS] [PLUGIN_NAME]...

Seed demo data for one, several, or all enabled plugins.

Options:
  --strict / --best-effort   Fail the command on the first plugin error
                             (default), or continue and report at the end.
  --json                     Emit machine-readable summary on stdout.

Each plugin's seed is idempotent — running 'seed all' twice is a no-op
the second time.

Examples:
  flask seed all
  flask seed meinchat subscription
  flask seed all --best-effort --json
```

**Plugin-side convention.** New, additive — plugins keep their
existing `populate_db.py` until they migrate:

```python
# plugins/subscription/__init__.py
class SubscriptionPlugin(BasePlugin):
    def populate(self) -> PopulateResult:
        from plugins.subscription.populate_db import seed
        return seed()      # returns {"created": int, "skipped": int, "errors": [...]}
```

Plugins without `populate()` fall back to running their
`populate_db.py` as a module (`runpy.run_path(...)` inside the
container) — *but with the exit-code propagation that today's seed
step lacks*.

**TDD shape:** `tests/unit/cli/test_seed_command.py` (NEW, ≥ 8 specs).

| # | Spec |
|---|---|
| 1 | `flask seed all` discovers every enabled plugin and calls each `populate()` once |
| 2 | `flask seed meinchat` calls only meinchat's `populate()` |
| 3 | `flask seed not_a_plugin` exits 2 with a clear "unknown plugin" message |
| 4 | A `populate()` raising → exit 1 in `--strict` mode (default) |
| 5 | A `populate()` raising → exit 0 in `--best-effort` mode but the JSON summary lists the error |
| 6 | A plugin without `populate()` falls back to `populate_db.py` and propagates its exit code |
| 7 | `--json` emits valid JSON with `{ "plugins": [{"name": …, "ok": bool, "created": int, "errors": […]}, …] }` |
| 8 | Disabled plugins are skipped silently (don't crash on a half-installed deploy) |

**Acceptance:**
- `docker compose exec api flask seed all` on a fresh dev DB seeds
  every enabled plugin's demo data without ad-hoc shell loops.
- A deliberate `raise Exception("boom")` in a plugin's `populate()` →
  `flask seed all` exits 1 with the plugin name in the message.

### Slice 1 — `GET /api/v1/_routes` introspection endpoint

**File added:** `vbwd-backend/vbwd/routes/debug/routes_catalog.py` (~30 LOC).

```python
@debug_bp.route("/_routes", methods=["GET"])
@require_debug_enabled
def list_routes():
    """Lists every registered route. Debug-only — gated by ENABLE_DEBUG_ENDPOINTS."""
    out = []
    for rule in current_app.url_map.iter_rules():
        for method in sorted(rule.methods - {"HEAD", "OPTIONS"}):
            view_func = current_app.view_functions.get(rule.endpoint)
            out.append({
                "method": method,
                "path": str(rule),
                "endpoint": rule.endpoint,
                "auth_required": _has_decorator(view_func, "require_auth"),
                "permission": _extract_required_permission(view_func),  # may be None
            })
    return jsonify({"routes": out})
```

**Debug gate.** New helper `vbwd/middleware/debug.py::require_debug_enabled`
returns `404` unless `current_app.config["ENABLE_DEBUG_ENDPOINTS"] is True`.
Default in prod images: `False`. Default in CI / dev: `True`. Single
env var (`VBWD_ENABLE_DEBUG_ENDPOINTS=1`) flips it.

**Why debug-gated.** Listing every registered route is information an
attacker would love (pre-recon for fuzzing private endpoints). Keep it
off in prod by default; CI / heavy-load harness opts in.

**TDD shape:** `tests/unit/routes/debug/test_routes_catalog.py` (NEW, ≥ 5 specs).

| # | Spec |
|---|---|
| 1 | With `ENABLE_DEBUG_ENDPOINTS=False`: `GET /api/v1/_routes` → 404 |
| 2 | With `ENABLE_DEBUG_ENDPOINTS=True`: returns a list containing every test-app route |
| 3 | Each entry has `method`, `path`, `endpoint`, `auth_required` keys (contract test) |
| 4 | Plugin-registered routes appear in the list (verified by enabling a stub plugin in the test app) |
| 5 | `auth_required: true` is set for routes decorated with `@require_auth` |

**Acceptance:**
- `curl http://localhost:5000/api/v1/_routes` in dev returns the
  expected catalog.
- S29 §3.2's smoke step consumes this endpoint and fails fast on URL
  drift.

### Slice 2 — `GET /api/v1/_seed_status` introspection endpoint

**File added:** `vbwd-backend/vbwd/routes/debug/seed_status.py` (~40 LOC).

```python
@debug_bp.route("/_seed_status", methods=["GET"])
@require_debug_enabled
def seed_status():
    """Per-plugin seed status. Debug-only."""
    manager = current_app.container.plugin_manager()
    out = {"seeded": [], "unseeded": [], "populated_at": {}}
    for plugin in manager.list_enabled():
        ts = _read_seed_marker(plugin.metadata.name)
        if ts is None:
            out["unseeded"].append(plugin.metadata.name)
        else:
            out["seeded"].append(plugin.metadata.name)
            out["populated_at"][plugin.metadata.name] = ts.isoformat()
    return jsonify(out)
```

**Seed markers.** Slice 0's `flask seed` writes a small row in a new
core table `vbwd_plugin_seed_marker(plugin_name PK, populated_at)` on
success. Removing the marker via `flask seed <name> --reset` is a
single statement.

**Migration.** One additive table (`alembic/versions/…_create_seed_marker.py`).
Backward compatible — plugins seeded by older `populate_db.py` runs
appear as unseeded until the next `flask seed` run; expected (this is
the test-harness diagnostic, not a production data path).

**TDD shape:** `tests/unit/routes/debug/test_seed_status.py` (NEW, ≥ 4 specs).

| # | Spec |
|---|---|
| 1 | Fresh DB: every enabled plugin is in `unseeded` |
| 2 | After `flask seed meinchat`: meinchat in `seeded`, others in `unseeded` |
| 3 | `populated_at` is an ISO timestamp |
| 4 | Disabled plugins don't appear in either list |

**Acceptance:**
- After `flask seed all`, `curl /api/v1/_seed_status` returns
  `{"unseeded": [], …}`. The harness post-seed step asserts this.

---

## 4. Coordination with S29

[S29](s30-heavy-load-harness-fixes.md) is the harness-side sprint and
can land alone. **But when both this sprint and S29 are in:**

- S29 §3.0 (seed step) becomes a one-liner:
  `docker compose exec -T api flask seed all`
  + a `curl /api/v1/_seed_status` assertion that `unseeded == []`.
- S29 §3.2 (scenario contract refresh) gets a proper smoke against
  `/api/v1/_routes` instead of a placeholder.

Either order works — S29 can ship first with the bespoke shell from
its §3.0 and the `if hasattr(server, "_routes")` no-op smoke, then
upgrade once this sprint lands.

---

## 5. Test plan (TDD-first across the three slices)

Aggregate test surface, all in `vbwd-backend/tests/unit/`:

- `cli/test_seed_command.py` (NEW, ≥ 8 specs).
- `routes/debug/test_routes_catalog.py` (NEW, ≥ 5 specs).
- `routes/debug/test_seed_status.py` (NEW, ≥ 4 specs).
- `middleware/test_require_debug_enabled.py` (NEW, ≥ 3 specs — 404
  by default, 200 when env set, env-flip is read at request time not
  at boot so flipping it in `pytest` fixtures works).

Plus one integration spec in `tests/integration/test_seed_full_loop.py`:
on a fresh test DB, `flask seed all` then `/api/v1/_seed_status`
returns `unseeded: []`.

`bin/pre-commit-check.sh --full` GREEN — 20 + new specs.

---

## 6. Acceptance — measurable end-state

- `docker compose exec api flask seed all` produces a clean idempotent
  seed; running it a second time results in `created: 0` everywhere.
- `curl /api/v1/_routes` in dev returns every registered route; each
  entry has the documented contract fields.
- `curl /api/v1/_seed_status` in dev returns the per-plugin marker
  set.
- All three endpoints return **`404`** in a prod-mode boot
  (`ENABLE_DEBUG_ENDPOINTS` absent / false).
- The heavy-load CI workflow updated by S29 picks these up (after
  S29's slice 3.2 is in place) and harness drift becomes a 1-second
  pre-load failure rather than a 2-minute threshold-breach failure.

---

## 7. Out of scope (kept here so they don't sneak back in)

- **Full OpenAPI emission.** Real product feature for SDK generation,
  not a test-hygiene one. New sprint when there's a real consumer.
- **Cross-cutting harness affordances** (e.g. a `fakeclock` endpoint,
  a `freeze_database` endpoint). YAGNI until a concrete scenario
  demands them.
- **Migrating each plugin's `populate_db.py` to the new
  `Plugin.populate()` method.** Optional — the CLI's `runpy` fallback
  keeps the old shape working. Migration is opportunistic per
  plugin's own touch-base.
- **Loadtest user pool seeded via this sprint's CLI.** Possible
  follow-up: S29's `LOADTEST_USERS` pool created by a dedicated
  `flask seed loadtest` plugin. Not in this sprint's scope; S29's
  inline list suffices.
- **Per-environment debug-gate granularity.** `ENABLE_DEBUG_ENDPOINTS`
  is one boolean. If we ever want "_routes on, _seed_status off"
  that's a follow-up flag split; today the harness wants both or
  neither.

---

## 8. Engineering-requirements check (BINDING)

- **TDD-first:** ≥ 20 new specs land across CLI + endpoints +
  middleware; specs precede the implementation per slice.
- **DevOps-first:** schema change for the seed-marker table is an
  Alembic migration; CI cold-start picks it up. Debug-gate flag
  documented in `.env.example`.
- **SOLID — S:** CLI is one module that *discovers* plugins and
  *delegates*; it doesn't know about any specific plugin's seed
  semantics.
- **SOLID — O:** plugins add behaviour by exposing the optional
  `populate()` method; no core change to add a new plugin.
- **SOLID — L:** the optional `populate()` is a substitute for the
  legacy `populate_db.py` shell — the CLI fallback honours the same
  exit-code contract.
- **SOLID — D (DI):** the CLI resolves plugins via the container's
  `plugin_manager`, not by walking the filesystem.
- **DRY:** the three new endpoints share the `require_debug_enabled`
  decorator; no per-endpoint debug-gate copy-paste.
- **NO OVERENGINEERING:** three small additions — CLI, two
  introspection endpoints — each solving exactly one of the three
  recurring harness-drift symptoms. No OpenAPI, no contract-test
  framework, no fixture system invented.
- **Core agnostic:** `_routes` and `_seed_status` live in
  `vbwd/routes/debug/`; the CLI iterates plugins via the existing
  plugin manager. No `from plugins.* import …` in core.
- **Quality gate:** `bin/pre-commit-check.sh --full` GREEN; manual
  smoke as documented in §6.

---

## 9. Anchor

Inherits the binding engineering requirements at
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
Companion to [S29 — heavy-load harness fixes](s30-heavy-load-harness-fixes.md);
motivated by [report 04](../reports/04-heavy-load-26452905684-harness-drift.md).
