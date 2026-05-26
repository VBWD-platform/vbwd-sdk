"""Heavy-load profile for the vbwd backend.

Triggered manually from the SDK's GitHub Actions UI (`Heavy Load` workflow); can
also be run locally against any reachable backend:

    locust -f tests/load/locustfile.py --host http://localhost:5000

Design + scenarios + acceptance criteria live in
`docs/dev_log/20260525/sprints/27-heavy-load.md`. The workflow uses
`--headless` + `--exit-code-on-error 1`, and we also signal a threshold breach
via `environment.process_exit_code` from the `quitting` listener at the bottom.

Endpoint reachability depends on which plugins are installed + enabled in the
target. A scenario whose endpoint 404s will be recorded as a failure — pick the
matching plugin set + `scenarios` input when launching the workflow, or run with
the default `plugins=all`.
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
    """Create a throwaway user; returns the JWT on success (or via fallback login)."""
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
    """Process-wide catalog snapshot. The catalog itself is exercised by
    ``AnonymousBrowse``; checkout VUs reuse this cache to avoid re-querying."""
    plans: list[dict[str, Any]] = []
    addons: list[dict[str, Any]] = []
    bundles: list[dict[str, Any]] = []

    @classmethod
    def warm(cls, client) -> None:
        if cls.plans:
            return
        try:
            cls.plans = client.get("/api/v1/tarif-plans").json().get("plans", []) or []
            cls.addons = client.get("/api/v1/addons").json().get("addons", []) or []
            cls.bundles = client.get("/api/v1/token-bundles").json().get("bundles", []) or []
        except Exception:  # noqa: BLE001 — catalog absence is a valid test state
            pass


# ── Scenarios (User classes, weighted) ───────────────────────────────────────

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
    """Write-heavy: plan + extras checkout. Each VU is a fresh user."""
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
            "token_bundle_ids": (
                [random.choice(_CatalogCache.bundles)["id"]] if _CatalogCache.bundles else []
            ),
            "add_on_ids": (
                [random.choice(_CatalogCache.addons)["id"]] if _CatalogCache.addons else []
            ),
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
    """Token-balance flow — exercises the token_payment plugin if installed."""
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
        # Non-destructive: computes how many tokens 1 USD would cost.
        self.client.post(
            "/api/v1/token-payment/quote",
            json={"amount": "1.00", "currency": "USD"},
            name="POST /token-payment/quote",
        )


class AdminQueries(HttpUser):
    """Admin pagination — exercises admin permission middleware + joins."""
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
    """Set ``environment.process_exit_code`` based on configured thresholds.
    The workflow also re-checks the CSVs; this provides an in-process signal."""
    fail_p95_ms = float(os.environ.get("LOAD_FAIL_P95_MS", "1500"))
    fail_pct_error = float(os.environ.get("LOAD_FAIL_PCT_ERROR", "1.0"))
    stats = environment.stats.total
    error_pct = (stats.num_failures / stats.num_requests * 100) if stats.num_requests else 0
    p95 = stats.get_response_time_percentile(0.95) or 0
    if error_pct > fail_pct_error or p95 > fail_p95_ms:
        environment.process_exit_code = 1
        print(
            f"THRESHOLD BREACH: error_pct={error_pct:.2f}% "
            f"(budget {fail_pct_error}%), p95={p95:.0f}ms (budget {fail_p95_ms}ms)"
        )
