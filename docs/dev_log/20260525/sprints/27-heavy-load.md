# Sprint 27 — Heavy load tests (manual GitHub Actions trigger)

**Risk:** LOW for the test code (it's additive — no prod code changes). MEDIUM
if run against a non-disposable target (always default to a CI-spun-up stack;
running against a deployed env is opt-in via input). **Outcome:** a Locust-based
heavy-load suite that can be triggered **manually** from the GitHub Actions UI
to stress the backend's hot paths (anonymous browse, authenticated dashboard,
checkout, token-payment, admin queries), with tunable parameters, HTML report
artifact, and pass/fail thresholds.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** — keep the suite minimal,
representative, and runnable from a cold start in CI without touching production
code. See [`_engineering-requirements.md`](_engineering-requirements.md). Gate:
the workflow's own pass/fail thresholds + a successful manual run on `main`.

## 1. Why this sprint

We have unit + integration coverage but **no load profile** of the backend. We
don't know:
- p95 / p99 latency under realistic concurrency on the hot paths.
- Whether the connection-pool/scheduler/EventBus survives sustained load.
- Where the first failure mode appears (DB pool? rate-limiter? plugin event handlers?).
- Whether new payment / checkout work (Sprint 11 extraction; token-payment;
  Sprint 27's own future plugin work) regresses headline numbers.

This sprint delivers a **runnable, parametric load-test suite** that anyone can
launch from the GitHub Actions UI — no local setup required.

## 2. Scope

**In scope.**
- A single Locust file (`tests/load/locustfile.py` in **`vbwd-platform`**)
  defining 5 user classes (one per scenario) with realistic task weights.
- One GitHub Actions workflow in `vbwd-platform`
  (`.github/workflows/heavy-load.yml`) triggered by `workflow_dispatch` only
  (never on push/PR) with tuning inputs — including a **plugin selector** so
  the operator picks which backend plugins to install + activate
  (default `all`).
- An idempotent seed step that uses the existing demo-data registry — never raw SQL.
- An HTML report uploaded as a workflow artifact.
- Pass/fail thresholds enforced as the job's exit code.

**Out of scope.**
- Frontend (Lighthouse / WebPageTest) — separate sprint.
- Long-soak (>10 min) runs — start short; add a "soak" preset later.
- Targeting deployed prod — flagged as opt-in input but **not** wired to prod
  secrets in this sprint.
- DB sizing / horizontal scale tests.

## 3. Design

### 3.1 Framework
**Locust 2.17.0** (already in `vbwd-backend/requirements.txt`; the
vbwd-platform workflow installs it on the runner with `pip install locust==2.17.0`
so the api Docker image stays untouched). Headless mode (`--headless`) in CI,
with `--html` for the artifact and `--exit-code-on-error 1` so threshold
breaches fail the job.

### 3.2 Target environment
The workflow spins up the **backend's own `docker-compose.yml`** (api + postgres
+ redis) inside the runner, just like `Plugin Tests / integration`. The default
target is `http://localhost:5000`. An opt-in `target_url` input lets a future
revision aim at staging — but this sprint **does not** wire credentials for any
deployed env; running against a deployed target requires the operator to set up
the URL + a fresh admin password manually.

### 3.3 Scenarios (User classes, weighted)

| User class | Weight | Flow | What it exercises |
|---|---|---|---|
| `AnonymousBrowse` | 6 | `GET /tarif-plans`, `GET /addons`, `GET /token-bundles` | public catalog read paths, Redis hot cache (if any) |
| `AuthedDashboard` | 4 | login → `GET /user/subscriptions/active` → `GET /user/addons` → `GET /user/invoices` | JWT verification, per-user repos, paginated queries |
| `CheckoutFlow` | 1 | login → `GET /tarif-plans/<slug>` → `POST /user/checkout` (plan + 1 bundle + 1 add-on) | `CheckoutHandler`, DI providers, line-item registry, invoice creation |
| `TokenBalancePay` | 1 | login → `GET /user/token-balance` → pick a pending invoice → `POST /token-payment/quote` → `POST /token-payment/pay` | `token_payment` plugin, capture seam, line-item handlers |
| `AdminQueries` | 1 | login as admin → `GET /admin/subscriptions` (paged) → `GET /admin/invoices` (paged) | admin permission middleware, pagination, joins |

Login is cached per virtual user (login once per user lifetime — `on_start`).
Each user picks a random plan/addon/bundle from the seeded catalog to avoid hot
keys.

### 3.4 Seeding (idempotent, service-layer only)
Reuse the existing demo-data registry: the workflow runs the catalog seeder
(plans + addons + bundles) and the test-data seeder (test users) **inside the
api container** via `docker compose exec` — no raw SQL. The seed step is
idempotent (cold-start safe), per the standing rule.

The CheckoutFlow user creates a **fresh user account per virtual user** at
`on_start` (random email) so checkout side-effects don't collide. AdminQueries
uses the seeded `admin@example.com` (read-only operations).

### 3.5 Tuning (workflow inputs)

| Input | Type | Default | Purpose |
|---|---|---|---|
| `users` | string (int) | `50` | concurrent virtual users |
| `spawn_rate` | string (int) | `5` | new users started per second |
| `duration` | string | `2m` | total run time (`30s`, `5m`, …) |
| `scenarios` | choice | `all` | `all` / `read-only` / `checkout-only` / `admin-only` |
| `target_url` | string | `http://localhost:5000` | override to point at staging (opt-in) |
| `fail_p95_ms` | string (int) | `1500` | p95 latency budget; breach → job fail |
| `fail_pct_error` | string (number) | `1.0` | % failed requests budget |

### 3.6 Pass/fail (enforced)
After the run, parse `report_stats.csv` and fail the job if:
- Aggregated failure rate > `fail_pct_error`, OR
- Any endpoint's p95 > `fail_p95_ms`, OR
- Any 5xx response was recorded.

## 4. Deliverables

Three files, all in **`vbwd-platform`** — added 2026-05-26 under
`vbwd-platform/tests/load/` and `vbwd-platform/.github/workflows/heavy-load.yml`.
The inlined content below is the source of truth for the spec; the live files
match it (modulo adapting the boot to vbwd-platform's `docker compose up -d
--build api postgres redis mailpit` pattern instead of running gunicorn
directly).

### 4.1 `tests/load/locustfile.py`

```python
"""Heavy-load profile — see docs/dev_log/20260525/sprints/27-heavy-load.md.

Run locally:
    locust -f tests/load/locustfile.py --host http://localhost:5000

In CI (headless, enforced thresholds): see .github/workflows/heavy-load.yml.
"""
from __future__ import annotations

import os
import random
import uuid
from typing import Any, Optional

from locust import HttpUser, between, events, task

ADMIN_EMAIL = os.environ.get("LOAD_ADMIN_EMAIL", "admin@example.com")
ADMIN_PASSWORD = os.environ.get("LOAD_ADMIN_PASSWORD", "AdminPass123@")
TEST_USER_PASSWORD = os.environ.get("LOAD_TEST_PASSWORD", "TestPass123@")


def _login(client, email: str, password: str) -> Optional[str]:
    with client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
        name="POST /auth/login",
        catch_response=True,
    ) as resp:
        if resp.status_code == 200:
            return resp.json().get("token")
        resp.failure(f"login failed: {resp.status_code} {resp.text[:120]}")
        return None


def _register(client, email: str, password: str) -> Optional[str]:
    """Create a throwaway user; returns the JWT on success."""
    with client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "name": email.split("@")[0]},
        name="POST /auth/register",
        catch_response=True,
    ) as resp:
        if resp.status_code in (200, 201):
            return resp.json().get("token") or _login(client, email, password)
        resp.failure(f"register failed: {resp.status_code} {resp.text[:120]}")
        return None


class _CatalogCache:
    """Process-wide catalog snapshot fetched once. Avoids every VU hitting the
    catalog at start; the catalog itself is exercised by AnonymousBrowse."""
    plans: list[dict[str, Any]] = []
    addons: list[dict[str, Any]] = []
    bundles: list[dict[str, Any]] = []

    @classmethod
    def warm(cls, client) -> None:
        if cls.plans:
            return
        cls.plans = client.get("/api/v1/tarif-plans").json().get("plans", []) or []
        cls.addons = client.get("/api/v1/addons").json().get("addons", []) or []
        cls.bundles = client.get("/api/v1/token-bundles").json().get("bundles", []) or []


# ── Scenarios ────────────────────────────────────────────────────────────────

class AnonymousBrowse(HttpUser):
    """Public catalog reads — heaviest weight, simulates window-shoppers."""
    weight = 6
    wait_time = between(0.5, 2.0)

    @task(3)
    def list_plans(self) -> None:
        self.client.get("/api/v1/tarif-plans", name="GET /tarif-plans")

    @task(2)
    def list_addons(self) -> None:
        self.client.get("/api/v1/addons", name="GET /addons")

    @task(1)
    def list_bundles(self) -> None:
        self.client.get("/api/v1/token-bundles", name="GET /token-bundles")


class AuthedDashboard(HttpUser):
    """Logged-in dashboard browsing: subscriptions, addons, invoices."""
    weight = 4
    wait_time = between(0.5, 2.0)

    def on_start(self) -> None:
        email = f"load+{uuid.uuid4().hex[:10]}@example.com"
        token = _register(self.client, email, TEST_USER_PASSWORD)
        self.client.headers["Authorization"] = f"Bearer {token}" if token else ""

    @task(3)
    def active_subscription(self) -> None:
        self.client.get("/api/v1/user/subscriptions/active", name="GET /user/subs/active")

    @task(2)
    def my_addons(self) -> None:
        self.client.get("/api/v1/user/addons", name="GET /user/addons")

    @task(2)
    def my_invoices(self) -> None:
        self.client.get("/api/v1/user/invoices", name="GET /user/invoices")


class CheckoutFlow(HttpUser):
    """Write-heavy: full plan + extras checkout. Each VU is a fresh user."""
    weight = 1
    wait_time = between(1.0, 3.0)

    def on_start(self) -> None:
        email = f"load+co-{uuid.uuid4().hex[:10]}@example.com"
        token = _register(self.client, email, TEST_USER_PASSWORD)
        self.client.headers["Authorization"] = f"Bearer {token}" if token else ""
        _CatalogCache.warm(self.client)

    @task
    def checkout(self) -> None:
        if not _CatalogCache.plans:
            return
        plan = random.choice(_CatalogCache.plans)
        self.client.get(f"/api/v1/tarif-plans/{plan['slug']}", name="GET /tarif-plans/<slug>")
        payload = {
            "plan_id": plan["id"],
            "token_bundle_ids": [random.choice(_CatalogCache.bundles)["id"]] if _CatalogCache.bundles else [],
            "add_on_ids": [random.choice(_CatalogCache.addons)["id"]] if _CatalogCache.addons else [],
        }
        with self.client.post(
            "/api/v1/user/checkout",
            json=payload,
            name="POST /user/checkout",
            catch_response=True,
        ) as resp:
            if resp.status_code not in (200, 201):
                resp.failure(f"checkout failed: {resp.status_code} {resp.text[:160]}")


class TokenBalancePay(HttpUser):
    """Token-balance pay flow — exercises the token_payment plugin + capture seam."""
    weight = 1
    wait_time = between(1.0, 3.0)

    def on_start(self) -> None:
        email = f"load+tk-{uuid.uuid4().hex[:10]}@example.com"
        token = _register(self.client, email, TEST_USER_PASSWORD)
        self.client.headers["Authorization"] = f"Bearer {token}" if token else ""

    @task(2)
    def balance(self) -> None:
        self.client.get("/api/v1/user/token-balance", name="GET /user/token-balance")

    @task(1)
    def quote(self) -> None:
        # quote against a small fixed amount; the endpoint is computational, not destructive
        self.client.post(
            "/api/v1/token-payment/quote",
            json={"amount": "1.00", "currency": "USD"},
            name="POST /token-payment/quote",
        )


class AdminQueries(HttpUser):
    """Admin pagination — exercises the admin permission middleware + joins."""
    weight = 1
    wait_time = between(1.0, 3.0)

    def on_start(self) -> None:
        token = _login(self.client, ADMIN_EMAIL, ADMIN_PASSWORD)
        self.client.headers["Authorization"] = f"Bearer {token}" if token else ""

    @task(2)
    def list_subscriptions(self) -> None:
        self.client.get(
            "/api/v1/admin/subscriptions?page=1&per_page=20",
            name="GET /admin/subscriptions",
        )

    @task(2)
    def list_invoices(self) -> None:
        self.client.get(
            "/api/v1/admin/invoices?page=1&per_page=20",
            name="GET /admin/invoices",
        )


# ── Threshold enforcement (parsed by the workflow after the run) ────────────

@events.quitting.add_listener
def _enforce_thresholds(environment, **_: Any) -> None:
    """Set environment.process_exit_code based on configured thresholds.
    The workflow also re-checks the CSV — this provides an in-process signal."""
    fail_p95_ms = float(os.environ.get("LOAD_FAIL_P95_MS", "1500"))
    fail_pct_error = float(os.environ.get("LOAD_FAIL_PCT_ERROR", "1.0"))
    stats = environment.stats.total
    error_pct = (stats.num_failures / stats.num_requests * 100) if stats.num_requests else 0
    p95 = stats.get_response_time_percentile(0.95) or 0
    if error_pct > fail_pct_error or p95 > fail_p95_ms:
        environment.process_exit_code = 1
        print(f"THRESHOLD BREACH: error_pct={error_pct:.2f}% p95={p95:.0f}ms")
```

### 4.2 `.github/workflows/heavy-load.yml`

```yaml
name: Heavy Load

# Manual only — never on push/PR. Running this against a wrong target could
# spam an environment, so it stays behind a deliberate click.
on:
  workflow_dispatch:
    inputs:
      users:        { description: 'Concurrent virtual users', default: '50' }
      spawn_rate:   { description: 'Spawn rate (users/sec)',   default: '5' }
      duration:     { description: 'Run time (e.g. 2m, 5m)',   default: '2m' }
      scenarios:
        description: 'Scenario preset'
        default: 'all'
        type: choice
        options: [all, read-only, checkout-only, admin-only]
      target_url:   { description: 'Override target URL (leave default for in-CI stack)', default: 'http://localhost:5000' }
      fail_p95_ms:  { description: 'p95 budget (ms); breach fails the job',  default: '1500' }
      fail_pct_error: { description: '% failed requests budget',             default: '1.0' }

jobs:
  load:
    name: Heavy load (${{ github.event.inputs.scenarios }}, ${{ github.event.inputs.users }} VU, ${{ github.event.inputs.duration }})
    runs-on: ubuntu-latest
    timeout-minutes: 30
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: vbwd, POSTGRES_PASSWORD: vbwd, POSTGRES_DB: vbwd }
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U vbwd"
          --health-interval 5s --health-timeout 3s --health-retries 10
      redis:
        image: redis:7
        ports: ['6379:6379']

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11', cache: 'pip', cache-dependency-path: requirements.txt }
      - run: pip install -r requirements.txt

      # Same plugin clone set as `Plugin Tests / integration` (full SDK boot).
      - name: Install ALL plugins
        run: |
          for plugin in analytics booking chat cms email ghrm mailchimp paypal stripe subscription taro token-payment yookassa; do
            git clone --depth=1 -q https://github.com/VBWD-platform/vbwd-plugin-${plugin}.git plugins/${plugin} 2>/dev/null || true
          done

      - name: Create plugins.json (enable all)
        run: |
          python3 -c "
          import json, os
          p = {d: {'enabled': True, 'version': '1.0.0', 'source': 'local'}
               for d in os.listdir('plugins')
               if os.path.isfile(os.path.join('plugins', d, '__init__.py'))}
          json.dump({'plugins': p}, open('plugins/plugins.json', 'w'))
          "

      - name: Migrate + seed (idempotent, service-layer)
        env:
          DATABASE_URL: postgresql://vbwd:vbwd@localhost:5432/vbwd
          REDIS_URL: redis://localhost:6379/0
        run: |
          alembic upgrade heads
          # Seed catalog + admin/test users via the demo-data registry (no raw SQL).
          python -c "from vbwd.app import create_app; from vbwd.services.demo_data_registry import seed_catalog, seed_test_data; \
                     app = create_app(); ctx = app.app_context(); ctx.push(); seed_catalog(); seed_test_data()"

      - name: Start API (gunicorn, detached)
        env:
          DATABASE_URL: postgresql://vbwd:vbwd@localhost:5432/vbwd
          REDIS_URL: redis://localhost:6379/0
          FLASK_ENV: production
        run: |
          gunicorn -w 4 -b 0.0.0.0:5000 "vbwd.app:create_app()" &
          for i in $(seq 1 30); do
            curl -sf http://localhost:5000/api/v1/health > /dev/null && break || sleep 2
          done

      - name: Run Locust (headless)
        env:
          LOAD_FAIL_P95_MS: ${{ github.event.inputs.fail_p95_ms }}
          LOAD_FAIL_PCT_ERROR: ${{ github.event.inputs.fail_pct_error }}
        run: |
          mkdir -p load-report
          # Translate the scenarios preset into Locust --tags / user-class filters.
          case "${{ github.event.inputs.scenarios }}" in
            read-only)     CLASSES="AnonymousBrowse AuthedDashboard" ;;
            checkout-only) CLASSES="CheckoutFlow" ;;
            admin-only)    CLASSES="AdminQueries" ;;
            *)             CLASSES="" ;;  # all
          esac
          locust -f tests/load/locustfile.py \
            --host "${{ github.event.inputs.target_url }}" \
            --headless \
            --users "${{ github.event.inputs.users }}" \
            --spawn-rate "${{ github.event.inputs.spawn_rate }}" \
            --run-time "${{ github.event.inputs.duration }}" \
            --csv load-report/stats \
            --html load-report/index.html \
            --exit-code-on-error 1 \
            ${CLASSES:+--class-picker} $CLASSES

      - name: Upload HTML report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: heavy-load-report-${{ github.run_number }}
          path: load-report/

      - name: Print summary
        if: always()
        run: |
          echo "::group::Aggregated stats"
          tail -n +1 load-report/stats_stats.csv
          echo "::endgroup::"
```

### 4.3 `tests/load/README.md`

A short pointer file — what the suite does, how to run locally, where to find
the workflow in the Actions UI, link back to this sprint doc.

## 5. Acceptance criteria

A slice is "done" when:

1. **Manual trigger works.** A maintainer can open `Actions → Heavy Load → Run
   workflow` on `main`, tweak inputs, and the job runs to completion.
2. **Defaults are green.** Default inputs (50 VU, 5/s spawn, 2m, all scenarios)
   against the in-CI stack complete with **0 5xx**, error rate < 1%, p95 ≤ 1.5 s.
3. **Threshold enforcement actually fails.** A deliberate `fail_p95_ms=10`
   (absurdly low) run **fails** the job with a clear "THRESHOLD BREACH" line in
   the logs — proving the gate is wired.
4. **Artifact uploaded.** The `heavy-load-report-<run>/index.html` is downloadable.
5. **No prod code changes.** Only `vbwd-platform/tests/load/*` +
   `vbwd-platform/.github/workflows/heavy-load.yml` are added; `vbwd-backend`,
   the plugin repos, `vbwd-platform/be/`, and any existing workflow are
   untouched.

## 6. Run instructions

**GitHub UI.** In the `vbwd-platform` repo: `Actions` → `Heavy Load` →
`Run workflow` → fill inputs → click. The `plugins` selector controls which
backend plugins get installed + activated for the run (default `all`).

**Locally.** From `vbwd-platform`, stack up (`docker compose up -d`), then:
```
cd vbwd-platform
pip install locust==2.17.0
locust -f tests/load/locustfile.py --host http://localhost:5000
# open http://localhost:8089 for the Locust UI, set VU / spawn rate, hit Start
```

## 7. Risk + safety

- **Default target is the in-CI stack** — running against a deployed env is
  explicitly opt-in via `target_url`. The workflow has no production secrets;
  pointing it at production would just fail to authenticate (no creds wired).
- **CheckoutFlow creates fresh users per VU** so the run doesn't trample shared
  state. The api container is torn down at job end (services lifecycle).
- **No raw SQL anywhere** (per the standing rule) — seeding goes through the
  demo-data registry.

## 8. Follow-ups (deliberately out of scope)

- **Soak preset** (`duration: 30m`, lower spawn) once we know the steady-state
  p95.
- **Trend dashboard.** Compare consecutive runs (e.g. parse `stats.csv` into a
  GitHub Pages chart). Today the artifact is per-run only.
- **Frontend** load (Lighthouse / WebPageTest).
- **Wiring a staging target** with read-only creds in repo secrets.
- **More plugins.** Add a scenario for each net-new revenue path as it ships
  (e.g., the upcoming `s12` token-balance-at-checkout flow once green).

## 9. References

- Locust docs — https://docs.locust.io/
- Standing project rules (schema only via Alembic; test/demo data only via
  services — never raw SQL) are captured in this repo's `CLAUDE.md` /
  `docs/dev_log/...` and applied above (the seed step uses
  `seed_catalog` / `seed_test_data` from `vbwd.services.demo_data_registry`).
- The vbwd-platform workflow follows this repo's existing
  `.github/workflows/ci.yml` convention (clone `vbwd-backend` into
  `be/vbwd-backend/`, then `docker compose up -d --build api postgres redis
  mailpit`, then `alembic upgrade heads`) — same boot path as `platform_tests`.
- Sprint-11 follow-through + core-standalone migration cleanup:
  [`../reports/06-session2-fixes-ci-and-core-plugin-migration-separation.md`](../reports/06-session2-fixes-ci-and-core-plugin-migration-separation.md).
