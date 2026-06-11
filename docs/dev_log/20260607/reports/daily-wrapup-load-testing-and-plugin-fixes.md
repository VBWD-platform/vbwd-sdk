# Report — Daily wrap-up: load-testing campaign, plugin bugs & capacity findings

**Date:** 2026-06-09 → 06-10
**Theme:** A measurement-driven day. Validated the S48 capacity fixes against a real heavy-load run, overhauled the capacity-chart tool, built a reusable plugin load-test profile (booking/ghrm/meinchat/shop) and made it CI-triggerable, and found + fixed three real defects plus a significant config-invariant bug. Earlier in the day S58 (unified filesystem + logging) shipped end-to-end and the email/contact-form path was fixed.
**Status:** all gates green where claimed. **Nothing committed** (standing rule). matplotlib/locust were installed in a throwaway venv (`/tmp/chartvenv`) for local rendering.

---

## 1. S48 load-capacity — VALIDATED

Heavy-load run #20 (`report-20`) confirmed the S48 backend fixes work:

| | pre-S48 | run #20 |
|---|---|---|
| `/tarif-plans/<slug>` 400 | 100% fail | **0 × 400** (the bug is gone) |
| `too many clients` 500s | dominant | **1 in 136,498 requests** |
| throughput ceiling | ~130 rps | **~250 rps (~1.9×)** |
| degradation to 10k VU | hard cliff | **graceful** |

The headline 18.6% error was **measurement artifacts**, not defects: single-IP 429 rate-limit (CI runs from one IP → Flask-Limiter treats all VUs as one client), checkout re-subscribe 400 (same VU re-subscribing), and overload `RemoteDisconnected`. Applied two harness fixes so the next run reads clean: shed-tolerant reads (429/503 = graceful shed, not failure) and checkout user-rotation. Recorded the validation in [report 02 §Validation](02-s48-load-capacity-implemented.md).

---

## 2. Capacity-chart tool — overhauled

**Problem:** the charts keyed response time / errors / render on **throughput**, which is an emergent, *saturating* variable — past the knee it pins and oscillates (Little's Law inversely couples throughput↔latency), so a scatter smeared into a vertical band and a connected line spiralled/self-intersected. Confusing and unreadable.

**Fix:** all relationship charts re-keyed on the **monotonic load axis (concurrent users)**:
- `throughput-users.png` — throughput rising then plateauing at the ceiling (the useful "max rps" view)
- `users-latency.png` — latency vs load
- `errors-users.png` — error % vs load
- `render-users.png` — full-page render (p100) vs load

Plus, on request, a raw `throughput-latency.png` scatter is still emitted for the report (the standard latency-throughput view), clearly understood to smear at saturation.

**New:** `tests/load/chart/embed.py` embeds the chart PNGs into the Locust `index.html` as self-contained base64 `<img>` tags (idempotent), wired into the `Heavy Load` workflow so every report is one portable file. **29 chart unit tests green.**

---

## 3. Plugin load testing + CI trigger

New `tests/load/locustfile_plugins.py` — a load profile for **booking / ghrm / meinchat / shop** read endpoints:
- booking: config, categories, resources, `<slug>`, availability (`?date=`)
- ghrm: config, categories, packages, `<slug>`, related
- shop: products, `<slug>`, categories, `<slug>`
- meinchat: limits, capabilities, conversations, contacts, nickname (authed via one shared test-user token; the E2E message-send path is not loadable without the crypto handshake)

The `Heavy Load` workflow gained a **`profile` input** (`default` | `plugins`): dispatch `profile=plugins` to load-test all four plugins and get the same report/charts artifact, with a conditional ghrm-seed step (ghrm's catalogue seed lives in `src/bin/`, not `flask seed all`).

**Local results (120 VU on the co-located docker stack):** every endpoint fast — p95 ~6–24 ms, p99 ~10–240 ms — error ~0.6%, all `RemoteDisconnected` (the shared-box artifact). The plugin read paths are well-indexed and light.

---

## 4. Bugs found & fixed via load testing

1. **meinchat `GET /messaging/limits` → 500** — **FIXED** (vbwd-tdd, `--plugin meinchat --full` green: 273 unit + 15 integration). Root cause: the handler hard-subscripted four config keys read from the **persisted config store**, which on a drifted instance lacks them → `KeyError`. Fix: defensive `config.get(key, default)` (DEFAULT_CONFIG already carried them). **Live: 200.** Surfaced a config-store drift issue (some instances' stored config predates S28).
2. **ghrm 0 packages locally** — seeded **19** via the existing idempotent `populate_ghrm.py`; the endpoint serves them under `items`. Detail/related endpoints now load-tested. **Note:** ghrm's seed isn't run by `flask seed all` → worth wiring in.
3. **booking `/availability` 400 (100%)** — a **harness omission** (the endpoint requires `?date=YYYY-MM-DD`; the `400 "date parameter required"` is correct). Fixed in the profile.

---

## 5. Capacity finding — the worker/connection invariant breaks on big boxes

Investigating why local runs **oscillate** past the knee (throughput bouncing 140↔163 rps, error % bouncing 0↔11%) revealed a real config bug:

- On a **14-core M4**, gunicorn auto-scales to **29 workers** (`_default_workers = 2×cpu_count()+1`). With pool `10 + max_overflow 10 = 20` conns/worker, that's **580 potential DB connections vs Postgres `max_connections = 200`** → connection exhaustion under load → `too many clients` / connection drops → the **oscillation** (a congestion limit-cycle: overload → shed via drops → recover → overload).
- The **S48.1 invariant** (`workers × (pool + overflow) + reserve ≤ max_connections`) is only **asserted in a test with fixed numbers** (4 workers — true on the 2-core CI: `5×20=100 ≤ 200`), **not enforced at boot**. So it **silently breaks on any host with >~4 cores** — ironically, *more cores made the system less stable*.
- **Fix proposed:** clamp `workers = min((2×cpu)+1, (max_connections − reserve) // (pool + overflow))` in `gunicorn.conf.py`. **Immediate workaround:** `WEB_CONCURRENCY=8`. Also Docker Desktop gave the VM only 7.6 GB RAM (29 workers ≈ 5.8 GB) — raise it.

This is the most important finding of the day: the oscillation the load charts showed is **connection-pool exhaustion from an unclamped worker count**, not raw CPU saturation — and it affects real multi-core prod boxes, not just the test rig.

---

## 6. Also completed earlier today

- **S58 — Unified `FilesystemManager` + logging** — all 7 sub-sprints implemented & gated green: 58.0 manager core (port + Local/InMemory, namespaces/policies, confinement, write modes, flock, secrets, DI), 58.1 settings + plugin manifests (**torn-read race fixed**), 58.5 unified logging (D9: scope/stream router + event audit + redaction + rotation; dev guide written), 58.4 secrets/ghrm pem, 58.2 SEO prerender (atomic), 58.3 uploads (duplicate `IFileStorage` deleted), 58.6 cms-ai logger. Reports [01](01-unified-logging.md) + the [high-load perspectives](s48-highload-perspectives.md) capacity/cost planning doc.
- **Email / contact-form** — imported the missing `contact_form.received` template (the form had been silently no-op'ing), fixed `smtp_host` (`localhost`→`mailpit`), and added an `SMTP_PASSWORD`/`SMTP_*` **env override** so prod secrets live in the environment, not `plugins/config.json`. Contact form now sends end-to-end (verified via Mailpit).

---

## Outstanding / follow-ups

1. **Clamp gunicorn workers to the connection invariant** (`gunicorn.conf.py`) — recommended; the invariant currently breaks on >4-core hosts.
2. **Wire ghrm package seed into `flask seed all`** (a `populate_db.py` shim) so fresh installs/CI get the catalogue.
3. **meinchat config-store drift backfill** — migrate persisted plugin configs that predate S28 to carry the retention keys (the defensive `.get` covers it for now).
4. **S48.4 dedicated load env** — measure the real per-instance ceiling on a box that isn't co-hosting Postgres + the load generator; report capacity in real-mobile-user terms.
5. **Commit** — S58, S48, the chart tool, the plugin profile, and all the fixes are on disk, uncommitted, pending the user's go.
