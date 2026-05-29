# Report — Heavy-load run #26452905684 — failed by harness drift, **not** by the API

**Date:** 2026-05-28
**Repo / workflow:** [`VBWD-platform/vbwd-platform`](https://github.com/VBWD-platform/vbwd-platform) — *Heavy Load* workflow, manual dispatch.
**Job:** `Heavy load — all · 50 VU · 2m · plugins=all` (id `77878510790`).
**Result:** ❌ failed with `THRESHOLD BREACH: error_pct=46.61% (budget 1.0%), p95=12ms (budget 1500.0ms)`.
**Artifact:** `heavy-load-report-4`.

---

## 0. TL;DR

The threshold guard did its job. **But none of the 2 079 failing requests are a real performance / capacity problem** — they're all driven by two broken parts of the *test setup*:

1. **Seed step partially failed.** Eight of the per-plugin
   `populate_db.py` scripts ran outside the API container and crashed
   with `ModuleNotFoundError: No module named 'vbwd'`, so the test
   database was missing the data the Locust scenario expects
   (subscriptions, invoices, addons, tarif-plans, token bundles).
2. **Locust scenario has drifted from the live API contract.** Wrong
   request fields, wrong URL prefixes, an unparameterised path literal
   `<slug>`, and a request flow that never carries the bearer to
   protected endpoints.

The backend itself is **healthy** at this load: p95 = 12 ms across the
full plugin set, max = 360 ms (all on `POST /auth/login` — bcrypt cost,
expected). The threshold breach is exclusively on `error_pct`, not on
latency.

**Right reaction:** treat the run as a *harness regression*, not an SLO
incident. Fix the seed step (4 lines of shell), refresh the scenario's
field/URL contract (one PR), then re-run. No production-side mitigation
is warranted.

---

## 1. What the test is

`Heavy Load` is a manually-dispatched workflow that:

1. Clones `vbwd-backend` + the selected plugin set (here: `all`).
2. Starts the full stack via `docker compose up`.
3. Runs Alembic migrations.
4. Calls each plugin's `populate_db.py` to seed demo data.
5. Verifies admin login.
6. Runs Locust with 50 virtual users, 2 minute duration, against
   `localhost:5000`, using a scenario file that exercises a mix of
   public + user + admin endpoints.
7. Prints the aggregated stats + uploads an HTML report.
8. **Fails the job** if `error_pct > 1.0%` or `p95 > 1500 ms`.

Steps 1–3 + 5 + 7–8 passed. Step **4 (seed)** and step **6 (Locust)**
both produced fatal-but-recoverable issues that combined into the
threshold breach.

---

## 2. What the run shows

### 2.1 Aggregate (the headline numbers)

```
4 460 requests
2 079 failures      → 46.61 % error rate (budget 1 %)
  p50 = 4 ms
  p95 = 12 ms       (budget 1 500 ms)
  p99 = 22 ms
  max = 360 ms      (only on POST /auth/login — bcrypt cost)
RPS ~ 37 / s sustained
```

**Read carefully:** the latency distribution is *excellent*. Even at
99 % the API answers in 22 ms. The 360 ms outliers are bcrypt during
login — the right behaviour, not a regression.

### 2.2 Per-endpoint result

| Endpoint | Req | Fails | Why |
|---|---|---|---|
| `GET /user/subs/active` | 584 | 100 % | `401 UNAUTHORIZED` — no bearer attached on user reads |
| `GET /user/invoices` | 411 | 100 % | same — `401` |
| `GET /user/addons` | 381 | 100 % | same — `401` |
| `POST /user/checkout` | 230 | 100 % | `401 Authorization header is required` |
| `GET /tarif-plans/<slug>` | 230 | 100 % | `400 BAD REQUEST` — literal `<slug>` in URL (no string interpolation) |
| `GET /user/token-balance` | 156 | 100 % | `404 NOT FOUND` — wrong path (no `/plugins/token-payment/…`) |
| `POST /token-payment/quote` | 64 | 100 % | `404 NOT FOUND` — same |
| `POST /auth/register` | 23 | 100 % | `400 "{'name': ['Unknown field.']}"` — scenario sends `name`, schema expects `first_name`/`last_name` |
| `POST /auth/login` | 4 | 0 % | succeeded — but only 4 logins for 50 VUs is a smell (most VUs never authenticated, see §3.2) |
| Everything else (`GET /addons`, `GET /tarif-plans`, `GET /token-bundles`, `GET /admin/invoices`, `GET /admin/subscriptions`, public `/api/v1/*` reads) | 2 377 | **0 %** | Healthy, fast |

The 100 %-fail rows are **deterministic harness bugs**, not capacity
limits — every request to those endpoints under any load would fail
the same way.

### 2.3 Seed-step diagnostics (the upstream cause)

The "Seed test users + plugin demo data" step logs eight identical
crashes:

```
populate c2p2
Traceback (most recent call last):
  File "/app/plugins/c2p2//populate_db.py", line 8, in <module>
    from vbwd.extensions import db
ModuleNotFoundError: No module named 'vbwd'
```

…repeated for `c2p2`, `checkout`, `conekta`, `mercado_pago`,
`promptpay`, `subscription`, `toss_payments`, `truemoney`.

Two things to notice:
- `meinchat` succeeded ("posted demo greeting"). Its `populate_db.py`
  must use a different entry path (e.g. shells in via the running API
  rather than importing `vbwd.*` directly).
- The path in the traceback contains a *double slash*
  (`/app/plugins/c2p2//populate_db.py`) — there's a `${PLUGIN_DIR}/`
  somewhere in the runner script with an unintended `/` at the end of
  `${PLUGIN_DIR}`. Cosmetic; doesn't change the cause.

The cause is that the populate scripts are being invoked **outside the
api container** (where `PYTHONPATH=/app` puts `vbwd.*` on the path) —
probably via `python plugins/<name>/populate_db.py` from the GH runner
shell. They need to run **inside** the container:
`docker compose exec api python plugins/<name>/populate_db.py`.

Even so, the step is marked ✓ by the workflow (it doesn't propagate the
script's exit code) — silent partial failure. **That's the most
important harness bug here:** the seed step looks green even when 8/9
plugins are unseeded.

### 2.4 Scenario / contract drift (the downstream cause)

The Locust scenario file (presumably `locustfile.py` in the
`vbwd-platform` repo) hasn't been updated alongside the API:

| Symptom in the run | Actual API contract | Where it drifted |
|---|---|---|
| `register failed: 400 {"error": "{'name': ['Unknown field.']}"}` | `auth_register` expects `first_name`/`last_name` (and friends), not `name` | Schema changed; scenario not updated |
| `GET /token-payment/quote` → 404 | route is `GET /api/v1/plugins/token-payment/quote` | URL prefix `/plugins/<id>/` not honoured in scenario |
| `GET /user/token-balance` → 404 | likely under `/plugins/token-payment/…` or wherever the token plugin's wallet read lives | URL drift |
| `GET /tarif-plans/<slug>` → 400 | scenario emitted the literal placeholder | f-string bug in scenario |
| User reads `→` 401 across the board | scenario never sets `Authorization: Bearer …` on the client session after a successful login | Session/state bug |

The fact that `POST /auth/login` succeeded **4 times** out of (at
minimum) the 50 VUs that ran their `on_start` is consistent with most
VUs failing to register first (the 23 `register` errors above) and
falling back to a shared seeded admin — but the bearer from that login
never persists into the per-VU client session, so every subsequent
authenticated read is `401`.

---

## 3. What the test does NOT show

It deliberately doesn't tell us anything about:

1. **API capacity at 50 VU.** Most user endpoints never got a single
   authenticated request to test. We learn nothing about how the
   subscription / invoice / token-payment endpoints behave under
   load.
2. **Plugin-set composition trade-offs.** "plugins=all" was the
   dispatch parameter, but only the unauthenticated public reads
   actually got exercised. A future run that fixes the harness will
   give the first real signal here.
3. **Lock contention, connection-pool exhaustion, scheduler interference.**
   None of these would be visible in a run dominated by 401/404
   pre-handler failures.

---

## 4. How to react

In order of effort vs. value. **None of these are production-side
changes** — every fix is in the test harness / scenario.

### 4.1 Block partial seed failures (15 minutes)

In `.github/workflows/heavy-load.yml`, change the seed step from a
forgiving loop to one that fails fast on a non-zero exit and runs
inside the api container:

```yaml
- name: Seed test users + plugin demo data
  run: |
    set -e
    for d in $(ls -d $GITHUB_WORKSPACE/vbwd-backend/plugins/*/); do
      plugin=$(basename "$d")
      if [ -f "$d/populate_db.py" ]; then
        echo "  populate $plugin"
        docker compose -f vbwd-backend/docker-compose.yml exec -T api \
          python plugins/$plugin/populate_db.py
      fi
    done
```

Two changes vs. today:
- `set -e` — first failure aborts the step.
- `docker compose exec` — runs inside the api container where
  `vbwd.*` is importable.

After this, eight more `populate_db.py` calls will produce real seed
data (or surface a *real* bug in one of them, which is also useful).

### 4.2 Add a per-VU `on_start` that sets the bearer header (1 hour)

In the Locust scenario, every authenticated `HttpUser` subclass should
do the register-or-login dance in `on_start` and store the resulting
bearer on `self.client.headers`:

```python
class AuthenticatedUser(HttpUser):
    abstract = True

    def on_start(self):
        # Use the pre-seeded loadtest user when available; fall back to
        # /auth/register only for stress-creates.
        creds = next_test_user()
        resp = self.client.post("/api/v1/auth/login",
                                json={"email": creds.email, "password": creds.password},
                                name="POST /auth/login")
        resp.raise_for_status()
        self.client.headers["Authorization"] = f"Bearer {resp.json()['token']}"
```

Drop the per-VU `auth_register` calls unless the scenario is
explicitly stressing registration — they're rate-limited by design and
will skew the error metric.

### 4.3 Refresh the field + URL contracts (1 hour)

Sweep the scenario file for the four contract drifts identified in §2.4:

- `auth_register` payload: `first_name` + `last_name` (+ whatever else
  the current `register_schema` requires).
- All `/token-payment/…` paths → `/plugins/token-payment/…`.
- `/user/token-balance` → check `plugins/token_payment/token_payment/routes.py`
  for the live path.
- `f"/tarif-plans/{slug}"` not `"/tarif-plans/<slug>"`.

A defensive check at the top of the file: a smoke test that hits each
endpoint once via `requests.get/post` and asserts non-4xx, before
Locust spawns. Catches drift on the next contract change.

### 4.4 Tighten the budget interpretation (30 minutes)

Today the threshold rule is `error_pct ≤ 1% AND p95 ≤ 1500ms`. After
the harness is fixed, consider splitting the budget so the next
breach communicates **why**:

```python
THRESHOLDS = {
    "harness_smoke_must_be_clean": 0.0,   # the smoke step from §4.3
    "error_pct":                  1.0,
    "p95_ms":                     1500.0,
    "p99_ms":                     3000.0,
}
```

The breach lines in the print-summary become *"reliability fail"* vs
*"latency fail"* vs *"harness fail"* — the next operator reading the
log can tell which lane to fix without re-doing the per-endpoint dig
that this report did.

### 4.5 Re-run before deciding anything else

After §4.1 + §4.2 + §4.3, dispatch the workflow again with the same
parameters (`50 VU · 2m · plugins=all`). Two outcomes possible:

- **Threshold passes** → the harness was the only problem. File this
  run as a closed regression and continue.
- **Threshold still fails** but with a different error mix → we'll
  have a real signal for the first time. Reading it on top of a clean
  harness is what the test exists for.

---

## 5. Sanity check on the API itself

Just to leave no room for ambiguity: the *successful* slice of this
run (≈ 2 380 requests on public read paths) shows the API performing
within an order of magnitude of what we'd hope for at 50 VU:

| route | p95 | p99 | count | fails |
|---|---|---|---|---|
| `GET /addons` | 10 ms | 21 ms | 732 | 0 |
| `GET /tarif-plans` | 12 ms | 20 ms | 1 056 | 0 |
| `GET /token-bundles` | 9 ms | 22 ms | 353 | 0 |
| `GET /admin/invoices` | 20 ms | 100 ms | 106 | 0 |
| `GET /admin/subscriptions` | 27 ms | 48 ms | 127 | 0 |

These are good numbers. No reason to think there's a hidden capacity
problem under the harness — but we won't know about the *authenticated*
paths until the harness is repaired.

---

## 6. Where to file the follow-ups

The four fixes in §4 are all in `VBWD-platform/vbwd-platform`
(workflow + scenario + threshold module). No `vbwd-backend` change,
no plugin change.

Suggest creating a single follow-up sprint in
`docs/dev_log/20260528/sprints/` — e.g.
`heavy-load-harness-fixes.md` — covering all four items as one
slice, since they form a coherent unit (no point fixing one without
the others).

---

## 7. Anchor

This report is filed under
[`docs/dev_log/20260528/reports/`](.) so it sits next to the rate-limit
reports from the same day. Linked from
[`../status.md`](../status.md) in the next status update.
