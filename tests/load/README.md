# Heavy-load tests

Backend heavy-load profile, triggered manually from the SDK's GitHub Actions UI.

## Run in CI (manual)

1. Open the SDK repo on GitHub → **Actions** → **Heavy Load** → **Run workflow**.
2. Tune the inputs (defaults are sensible — 50 VU, 5/s spawn, 2 min, all
   scenarios, full plugin set).
3. Wait for the job to finish, then download the `heavy-load-report-<run>`
   artifact for the Locust HTML report (`load-report/index.html`) and CSVs.

### Inputs at a glance

| Input | Default | Notes |
|---|---|---|
| `plugins` | `all` | Comma-separated names, or `all`. Controls **which backend plugins are installed + activated** in the target stack |
| `backend_ref` | `main` | git ref of `vbwd-backend` to clone |
| `users` | `50` | concurrent virtual users |
| `spawn_rate` | `5` | new users started per second |
| `duration` | `2m` | total run time (`30s`, `5m`, …) |
| `scenarios` | `all` | preset: `all` / `read-only` / `checkout-only` / `admin-only` / `token-pay-only` |
| `target_url` | `http://localhost:5000` | override to point at a deployed env (opt-in; no prod creds wired) |
| `fail_p95_ms` | `1500` | p95 latency budget — breach fails the job |
| `fail_pct_error` | `1.0` | % failed requests budget — breach fails the job |

The `plugins=all` preset installs the full backend SDK as of today:
`analytics booking c2p2 chat checkout cms conekta email ghrm mailchimp meinchat
mercado-pago paypal promptpay stripe subscription taro token-payment
toss-payments truemoney yookassa`. Repos that don't (yet) exist in the org are
skipped, so the list can be tightened later without breaking the run.

If you pick a subset, make sure the `scenarios` preset matches — e.g.
`plugins=stripe,paypal,token-payment` should pair with `scenarios=token-pay-only`,
not `all` (otherwise the catalog / admin scenarios will 404 on absent plugins
and trip the error-rate threshold).

## Run locally

Backend stack up (`cd vbwd-backend && make up`), then from the SDK root:

```
pip install locust==2.17.0
locust -f tests/load/locustfile.py --host http://localhost:5000
# open http://localhost:8089 for the Locust web UI
```

Or headless with the same thresholds as CI:

```
LOAD_FAIL_P95_MS=1500 LOAD_FAIL_PCT_ERROR=1.0 \
locust -f tests/load/locustfile.py --host http://localhost:5000 \
  --headless --users 50 --spawn-rate 5 --run-time 2m \
  --csv /tmp/load-stats --html /tmp/load.html --exit-code-on-error 1
```

## Files

- `locustfile.py` — 5 weighted user classes:
  `AnonymousBrowse` (catalog read), `AuthedDashboard` (logged-in browse),
  `CheckoutFlow` (write-heavy), `TokenBalancePay` (token plugin),
  `AdminQueries` (admin pagination).
- `../../.github/workflows/heavy-load.yml` — the manual-trigger workflow.

Design + scenarios + acceptance criteria:
[`docs/dev_log/20260525/sprints/27-heavy-load.md`](../../docs/dev_log/20260525/sprints/27-heavy-load.md).
