# S29 — Heavy-load test harness fixes (workflow + Locust scenario)

**Status:** ✅ DONE & VALIDATED — 2026-06-02 ([report 12](../reports/12-s29-heavy-load-harness-complete.md) code; [report 13](../reports/13-heavy-load-validated-engine-speed.md) live run).
All 4 slices implemented + 15 harness unit specs + `loadtest_unit` CI job. The §5
acceptance gate is **met**: heavy-load run `26848354627` (50 VU · 2m · plugins=all)
runs end-to-end and **fails only on a real backend signal** (`/tarif-plans/<slug>`
100% — a genuine reliability finding), NOT harness drift. Latency/throughput green
(p95 88 ms, p99 330 ms, ~37 req/s). The path here caught two real defects loudly:
the S30 `flask seed` argv bug (backend `4f2c8d4`) and a slash-matching false
positive in the smoke (platform `0a1a880`) — each fixed with a regression test.
As-built: doc guessed `loadtest/…`; reality `tests/load/locustfile.py`, drift
verified vs backend source (register `name`, `tokens/balance`,
`plugins/token-payment/quote` GET+query, admin limit/offset).
**Original status:** PLANNED — 2026-05-28
**Triggered by:** [Run #26452905684 — 46.61 % error rate caused by harness drift](../reports/04-heavy-load-26452905684-harness-drift.md).
**Repo:** `VBWD-platform/vbwd-platform` (workflow + Locust scenario + threshold module).
**Track:** independent. **No `vbwd-backend` change in this sprint** — code-side affordances live in [S30](s30-load-test-code-affordances.md).
**Depends on:** none. (Co-operative with S30: §2.1 of this sprint can be simplified once S30's `flask populate all` CLI ships, but each can land alone.)

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · clean code · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** Heavy-load workflow re-dispatched with parameters identical to #26452905684 (`50 VU · 2m · plugins=all`) returns exit 0 — i.e. **either passes the threshold or fails on a real performance signal** (not on harness drift).

---

## 1. Goal

Every failure in the next heavy-load run is meaningful — caused by API
behaviour under load, not by a test-harness contract bug or a silently
incomplete seed step. Concretely:

1. The seed step **fails the job** if any `populate_db.py` exits non-zero.
2. The seed scripts run **inside** the api container so `vbwd.*` is importable.
3. The Locust scenario carries the bearer through every user-scoped request.
4. Every URL + payload in the scenario matches the live API contract; a
   pre-load smoke step proves it before any VU spawns.
5. The threshold module reports *why* a run failed (harness / reliability /
   latency), so the next operator reading the log doesn't have to do the
   manual triage that produced
   [report 04](../reports/04-heavy-load-26452905684-harness-drift.md).

---

## 2. What the broken run showed

Reference: [report 04](../reports/04-heavy-load-26452905684-harness-drift.md).
Summary for context: 4 460 requests, 2 079 failures (46.61 %), but
**p95 = 12 ms**. Every failure is one of four patterns, all on the
harness side:

| Pattern | Count | Diagnosis |
|---|---|---|
| `GET /user/<thing>` → `401` | 1 376 | Bearer never set on the per-VU client session |
| `POST /user/checkout` → `401` | 230 | Same — bearer missing |
| `GET /tarif-plans/<slug>` → `400` | 230 | Scenario emitted the literal `<slug>` placeholder (no f-string) |
| `GET /user/token-balance` + `POST /token-payment/quote` → `404` | 220 | Scenario uses `/token-payment/…`; real path is `/plugins/token-payment/…` |
| `POST /auth/register` → `400 Unknown field 'name'` | 23 | Schema expects `first_name`/`last_name`; scenario sends `name` |
| 8 of 9 `populate_db.py` crashed silently | — | Ran from the GH runner shell where `vbwd.*` isn't on `PYTHONPATH`; step still ✓ |

---

## 3. Slices

Four mechanical fixes. Each is small enough to PR independently; ship
them in this order so the next dispatch picks them up cleanly.

### Slice 0 — Seed step fails fast and runs in-container

**File:** `.github/workflows/heavy-load.yml` (the "Seed test users +
plugin demo data" step).

**Current shape:**

```yaml
- name: Seed test users + plugin demo data
  run: |
    for d in $(ls -d vbwd-backend/plugins/*/); do
      plugin=$(basename "$d")
      if [ -f "$d/populate_db.py" ]; then
        echo "  populate $plugin"
        python "$d/populate_db.py" || true   # ← swallows failure
      fi
    done
```

**Fixed shape:**

```yaml
- name: Seed test users + plugin demo data
  run: |
    set -euo pipefail
    cd vbwd-backend
    failures=0
    for d in plugins/*/; do
      plugin=$(basename "$d")
      if [ -f "${d}populate_db.py" ]; then
        echo "::group::populate ${plugin}"
        if ! docker compose exec -T api python "${d}populate_db.py"; then
          echo "::error::populate_db.py failed for plugin '${plugin}'"
          failures=$((failures + 1))
        fi
        echo "::endgroup::"
      fi
    done
    if [ "$failures" -ne 0 ]; then
      echo "::error::${failures} plugin(s) failed to seed; aborting"
      exit 1
    fi
```

Two semantic changes:
- `docker compose exec -T api python …` — runs inside the container where
  `PYTHONPATH=/app` and `vbwd.*` is importable.
- Explicit failure accumulator + `exit 1` — surfaces the silent partial
  failure that today's run hid.

The double-slash bug in the traceback path (`/app/plugins/c2p2//populate_db.py`)
is fixed incidentally by `${d}populate_db.py` (no trailing slash).

**TDD shape:**
A workflow-level test is hard to write inline; instead, the slice ships
with a one-shot characterisation script `bin/loadtest/repro-seed-bug.sh`
that deliberately introduces an `import vbwd.this_module_does_not_exist`
into a throwaway plugin's `populate_db.py`, runs the seed step locally,
and asserts the step exits non-zero. Re-runs to confirm the green path:
remove the throwaway → seed step exits zero. Manual; ~5 min to verify
end-to-end on the operator's laptop.

**Acceptance:**
- Re-dispatching the same heavy-load run before the other slices land
  now **fails at the seed step** (not silently downstream). That's the
  desired exit signal — failing fast is the win.

### Slice 1 — Locust scenario `on_start` propagates the bearer

**File:** the Locust scenario file in `VBWD-platform/vbwd-platform`
(commonly `locustfile.py` or `loadtest/scenarios/full.py`).

**Change:** every authenticated `HttpUser` subclass gets an `on_start`
that either logs in a pre-seeded loadtest user *or* registers a fresh
one (the register path is rate-limited by design — see S26 — so don't
hammer it), then sets `self.client.headers["Authorization"] = f"Bearer {token}"`.

```python
class AuthenticatedUser(HttpUser):
    abstract = True

    def on_start(self) -> None:
        creds = LOADTEST_USERS.next()
        resp = self.client.post(
            "/api/v1/auth/login",
            json={"email": creds.email, "password": creds.password},
            name="POST /auth/login",
        )
        resp.raise_for_status()
        self.client.headers["Authorization"] = f"Bearer {resp.json()['token']}"
```

`LOADTEST_USERS` is a small pool seeded by S30 (`flask seed loadtest`
creates N users with deterministic credentials). Until S30 ships, the
slice can ship with the pool inlined in the scenario (50 user objects
with `email=f"loadtest-{i}@example.com"`, `password="LoadTest123@"`)
and a `bin/seed_loadtest_users.sh` runner-side helper.

**TDD shape:**
A `pytest`-style scenario unit test in `loadtest/tests/test_scenario_units.py`
(NEW) instantiates `AuthenticatedUser` with a `MagicMock` client and
asserts:
1. `on_start` calls `POST /api/v1/auth/login` exactly once.
2. On a 200 response, the next call on `self.client` carries the
   `Authorization` header.
3. On a non-200, `raise_for_status()` propagates.

`requests-mock` makes this 30 LOC; the existing `vbwd-platform`
`requirements-loadtest.txt` already has `requests`.

**Acceptance:**
- After this slice + the seed slice, the `401 UNAUTHORIZED` count on
  `/user/<thing>` and `POST /user/checkout` drops to **zero** (or
  whatever the real auth failures look like once the contract is right).

### Slice 2 — Refresh the scenario's URL + payload contracts

**Same file as slice 1.** Sweep for the four documented drifts:

| Today (scenario) | Live API contract | Fix |
|---|---|---|
| `POST /auth/register` with `{"name": …}` | schema expects `first_name`, `last_name`, `email`, `password` | rewrite payload |
| `POST /token-payment/quote` | `POST /api/v1/plugins/token-payment/quote` | URL prefix |
| `GET /user/token-balance` | `GET /api/v1/plugins/token-payment/balance` (or equivalent — confirm via S30's `/api/v1/_routes`) | URL prefix |
| `GET /tarif-plans/<slug>` (literal `<slug>`) | `GET /api/v1/tarif-plans/{slug}` with a real slug | f-string interpolation |

Plus a small pre-flight smoke at the top of the scenario file:

```python
SCENARIO_URLS = [
    ("GET",  "/api/v1/health"),
    ("GET",  "/api/v1/tarif-plans"),
    ("GET",  "/api/v1/token-bundles"),
    ("GET",  "/api/v1/addons"),
    ("GET",  "/api/v1/plugins/token-payment/balance"),
    ("POST", "/api/v1/auth/register"),
    # …
]

@events.test_start.add_listener
def _validate_contract(environment, **kwargs) -> None:
    """Single-shot smoke before any VU spawns. Fails the run early if
    the scenario's URL list doesn't match the server's registered
    routes — drift becomes a 1-second failure, not a 2-minute one."""
    routes = requests.get(f"{environment.host}/api/v1/_routes").json()["routes"]
    known = {(r["method"], r["path"]) for r in routes}
    missing = [u for u in SCENARIO_URLS if u not in known]
    if missing:
        raise SystemExit(f"scenario drift — server doesn't expose: {missing}")
```

`/api/v1/_routes` ships in [S30](s30-load-test-code-affordances.md);
until then, the smoke is a no-op decorated with `if hasattr(server, "_routes")`.

**TDD shape:**
The scenario's `test_scenario_units.py` (from slice 1) gains:
1. A spec asserting `SCENARIO_URLS` includes one entry per task
   declared in the scenario classes (use the `@task` decorator's
   `__name__` to derive an expected URL; static check).
2. A spec instantiating each `HttpUser` task body and asserting the
   request URL doesn't contain unparameterised `<…>` placeholders
   (regex check `r"<[^>]+>"`).
3. A spec mocking `requests.get("/api/v1/_routes")` to return a stub
   list missing one URL → `_validate_contract` raises.

**Acceptance:**
- The `400`/`404` row count on the patterns listed above drops to zero.
- A deliberate one-character break in any URL (e.g. typing
  `/api/v1/tarrif-plans`) causes the workflow to fail at smoke time,
  not 2 minutes later at threshold time.

### Slice 3 — Threshold module returns a *typed* failure reason

**File:** the budget / threshold module (commonly
`loadtest/thresholds.py` or inlined in the workflow's "Print summary"
step).

**Today:** one boolean check
`error_pct <= 1.0 AND p95 <= 1500ms` → emits one line on failure.

**After:**

```python
THRESHOLDS = {
    "harness_smoke":      ("must_be_clean", None),     # asserted by Slice-2 smoke
    "error_pct":          ("<=", 1.0),                 # %
    "p95_ms":             ("<=", 1500.0),
    "p99_ms":             ("<=", 3000.0),
    "min_throughput_rps": (">=", 20.0),
}

def evaluate(stats: dict) -> tuple[int, list[str]]:
    """Returns (exit_code, breach_messages). Exit-code = 1 iff any
    breach. Messages are emitted in the typed form
    'BREACH category=<key> actual=<x> budget=<y>' so the post-mortem
    script + the GitHub Actions summary can group by category."""
```

The categories give the operator a one-line answer to "which lane to
fix":

| Category | Means |
|---|---|
| `harness_smoke` | Pre-load contract validation failed; nothing to debug load-wise |
| `error_pct` | Reliability breach — real or harness; check per-endpoint table |
| `p95_ms` | Latency breach at the user-visible percentile — usually a real perf issue |
| `p99_ms` | Tail latency — typically a contention / scheduler issue |
| `min_throughput_rps` | Throughput breach — VUs hit a serialised bottleneck (Redis, DB write lock, GIL) |

**TDD shape:**
`loadtest/tests/test_thresholds.py` (NEW), ≥ 8 specs covering each
budget independently:
1. All within budget → exit 0, no breach.
2. `error_pct` over → exit 1, one breach line with category, actual,
   budget.
3. `p95_ms` over → same shape.
4. `p99_ms` over → same shape.
5. `min_throughput_rps` under → same shape.
6. Multiple categories breached → all breach lines emitted (not just the
   first).
7. `harness_smoke` failure → preempts every other check (no point
   measuring latency on a contract-broken run).
8. Zero requests recorded (catastrophic boot failure) → emits a
   distinct `no_data` breach instead of a misleading `error_pct=0%`.

**Acceptance:**
- The workflow's job-summary panel renders one line per breach with
  the typed category. A future regression makes triage a 30-second
  glance instead of the half-hour log dig that produced report 04.

---

## 4. Test plan (TDD-first across the four slices)

Aggregate test surface added in this sprint, all in
`VBWD-platform/vbwd-platform`:

- `loadtest/tests/test_scenario_units.py` (NEW, ≥ 6 specs across slices 1–2).
- `loadtest/tests/test_thresholds.py` (NEW, ≥ 8 specs in slice 3).
- `bin/loadtest/repro-seed-bug.sh` (NEW, slice 0; ad-hoc verification, not part of CI).

Plus a new CI job (`loadtest-unit`) that runs the two pytest files
against every PR to `vbwd-platform`. Cheap (~30 s) — keeps the
scenario healthy between full heavy-load dispatches.

---

## 5. Acceptance — the only that matters

Re-dispatch the heavy-load workflow with the same parameters as
#26452905684 (`50 VU · 2m · plugins=all`). Two acceptable outcomes:

- **Threshold passes.** Production-side is in fact healthy at this
  load with this plugin set — closing this sprint *and* the harness-
  regression incident.
- **Threshold still fails, but each breach is one of `error_pct`,
  `p95_ms`, `p99_ms`, or `min_throughput_rps`** — i.e. a *real*
  production-side signal that needs investigation. The harness has
  done its job for the first time, and the next sprint is a real
  perf-tuning sprint, not another harness fix.

Either way, this sprint closes the day the next dispatch's failure
mode is no longer "harness drift."

---

## 6. Out of scope

- **OpenAPI emission from the backend.** The `/api/v1/_routes`
  catalogue used by Slice 2's smoke is a flat introspection endpoint —
  not a full OpenAPI spec. Full OpenAPI is a separate workstream; this
  sprint only needs "is this URL registered?" granularity.
- **k6 / Gatling / wrk migration.** Locust is what we have and what
  the team knows. No tool change in this sprint.
- **Cloud-driver-based runs.** Today the workflow runs on a
  github-hosted runner. Moving to a self-hosted larger instance or to
  k6-cloud is a capacity discussion, not a harness one.
- **Pre-prod / staging targets.** Heavy-load runs against the
  ephemeral docker-compose stack in CI. Pointing it at staging
  intentionally is a separate ops decision.

---

## 7. Engineering-requirements check

- **TDD-first:** every code-side change in slices 1–3 lands with a
  pytest spec; slice 0 is a workflow shell change with an explicit
  characterisation script. The deliberate-bug-injection check for
  slice 0 catches future "step looks green but did nothing" regressions.
- **DevOps-first:** the `loadtest-unit` job runs on every PR — drift
  caught before any heavy-load dispatch is needed.
- **SOLID — S/D:** the threshold module becomes a pure function of
  stats input → exit-code + messages (slice 3). Testable without a
  running Locust process.
- **DRY:** one source of truth for the URL catalogue
  (`SCENARIO_URLS`); the smoke + the runtime requests read from the
  same list.
- **NO OVERENGINEERING:** the four slices solve exactly the four
  failure patterns identified in report 04. No speculative
  "test-the-test" framework, no OpenAPI generation, no
  scenario-as-code DSL.
- **Quality gate:** Heavy-load re-dispatch + `loadtest-unit` job on
  every PR.

---

## 8. Anchor

Inherits the binding engineering requirements at
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md)
and the [heavy-load report 04](../reports/04-heavy-load-26452905684-harness-drift.md)
that motivated this sprint.
