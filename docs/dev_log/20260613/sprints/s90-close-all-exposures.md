# S90 — Close all exposures: production hardening, env/logging switch, RC-1 pre-rollout gate

**Status:** PLANNED — 2026-06-14
**Repos:** `vbwd-backend` (route-exposure oracle, log-level switch, debug-endpoint lockdown, prod-readiness command) · `vbwd-fe-admin` / `vbwd-fe-user` (plugin `debug_mode` audit, no prod console noise) · `vbwd-demo-instances` (prod `.env` + compose + nginx hardening) · `docs/` (the RC-1 pre-rollout checklist + the dev↔prod environment-switch guide with screenshots).
**Track:** release-gating. **Why now:** we are about to tag every module **RC-1** and open **public beta**. Endpoints that are perfect for local development (route catalog, seed status, verbose logging, plugin introspection) become **information-disclosure and DDoS-amplification surfaces** on a public instance, and uncapped `info`-level logging fills the disk. This sprint makes the dev↔prod boundary **explicit, tested, and one-switch**, and leaves behind a **durable guard** so a new endpoint can't ship unprotected again.

**Depends on / builds on (all exist today):**
- Auth middleware: `vbwd/middleware/auth.py` — `@require_auth`, `@require_admin`, `@require_permission`, `@require_user_permission`, `@optional_auth`; each stamps an introspectable marker (`requires_auth=True`, `required_permission=…`) on the view.
- Debug-endpoint gate: `vbwd/middleware/debug.py` `@require_debug_enabled` (returns **404** when off, hiding existence) guarding `GET /api/v1/_routes` (`vbwd/routes/debug/routes_catalog.py`) and `GET /api/v1/_seed_status` (`vbwd/routes/debug/seed_status.py`), keyed off `app.config["ENABLE_DEBUG_ENDPOINTS"]` (env `VBWD_ENABLE_DEBUG_ENDPOINTS`, default off).
- Config classes: `vbwd/config.py` — `DevelopmentConfig(DEBUG=True)`, `TestingConfig`, `ProductionConfig(DEBUG=False)` (the latter **already** rejects default `FLASK_SECRET_KEY`/`JWT_SECRET_KEY` — raises `ValueError`). Selected by `FLASK_ENV` via `get_config()`.
- Unified logging: `vbwd/services/logging/` (`router.py`, `config.py`) — per-stream files under `${VBWD_VAR_DIR:-/app/var}/logs/{core,<plugin>}/…`; rotation via `VBWD_LOG_MAX_BYTES` (10 MiB) + `VBWD_LOG_BACKUPS` (5); installed by `_install_unified_logging()` in `vbwd/app.py` (skipped under `TESTING`).
- Gunicorn: `gunicorn.conf.py` / `container/python/gunicorn.conf.py` — `loglevel = os.getenv("LOG_LEVEL", "info")`; access/error to stdout/stderr (host) or `/app/logs/*.log` (container).
- S30 affordances (`/_routes`, `/_seed_status`) and the per-route auth markers — the oracle reuses both.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** (the oracle + log switch + readiness command are core; nothing reads a plugin domain field) · **NO OVERENGINEERING** (the narrowest change that closes the exposure and proves it stays closed) — [`_engineering_requirements.md`](_engineering_requirements.md). **No new lint/type suppressions** without explicit approval ([[feedback_no_noqa_without_permission]]); dead-code removal is confirmed unused first. Schema changes (none expected) would be Alembic-only.
**Gate:** `bin/pre-commit-check.sh --full` green on every touched repo; the new **route-exposure oracle** green; a fresh `ProductionConfig` boot with the documented prod `.env` passes the new `flask prod-readiness` check with **zero findings**.

---

## 1. Goal

One sentence: **make "is this safe to expose publicly?" a test, not a memory.**

Three concrete outcomes:

1. **Every route is provably either intentionally-public (allow-listed) or auth-protected** — enforced by a CI oracle, so the answer to "are all CRUD requests protected?" is a green test on every push, not a manual re-audit.
2. **One switch flips dev↔prod** for the three things that matter — debug endpoints **off**, Flask `DEBUG` **off**, log verbosity **down** — all driven by env vars that the prod compose sets, documented in one place, and verified by a `flask prod-readiness` command.
3. **An RC-1 pre-rollout checklist** (partly automated, fully documented with screenshots) that a release manager runs before tagging RC-1 / opening beta.

> **What this sprint is NOT:** a rewrite. The audit (below) found the foundation is sound — consistent decorators, debug endpoints already gated, prod secrets already validated. The work is to **verify exhaustively, close the few real gaps, and make the good state permanent.**

---

## 2. Audit — verified against current source (2026-06-14)

### 2.1 What is already correct (keep, don't touch — just assert it in tests)

- **Auth is consistent across admin routes.** Every mutating admin route sampled (`routes/admin/users.py`, `currency.py`, `plugins.py`, `data_exchange.py`, `api_keys.py`) carries `@require_auth` + a `@require_permission("…")`. Plugin enable/disable is `settings.system`-gated (`routes/admin/plugins.py:181/206`, `routes/admin/frontend_plugins.py:168/176`).
- **Plugin-status endpoints are protected** — `GET /api/v1/admin/plugins` (`routes/admin/plugins.py:71`) requires `settings.view`; `GET /api/v1/admin/frontend-plugins/<app>` requires `settings.system`. *(The user's "plugins status endpoint" worry — confirmed already behind admin auth.)*
- **Dev/debug endpoints are gated + default-off** — `/_routes`, `/_seed_status` return **404** unless `VBWD_ENABLE_DEBUG_ENDPOINTS` is truthy.
- **Prod config self-validates** — `ProductionConfig` refuses to boot with the dev secret keys (`vbwd/config.py:178-200`). No hardcoded `debug=True` anywhere; `DEBUG` is config-class-driven only.
- **Data-exchange import is double-gated** — `@require_admin` + entity-level permission + **superadmin** for `replace_all` (`routes/admin/data_exchange.py:151/304`).

### 2.2 The real gaps (what this sprint closes)

| # | Gap | Evidence | Risk at public beta |
|---|---|---|---|
| **G1** | **No global auth guard — protection is per-route decorator only.** A new route with a forgotten decorator is **silently public**. There is `before_request` only for DI container wiring (`app.py:257-260`), no auth sweep. | `app.py` blueprint registration; auth is opt-in per view. | A single missed decorator on a future CRUD route = an open mutation/exfiltration endpoint that nothing catches. **This is the keystone risk.** |
| **G2** | **`LOG_LEVEL` does not throttle the application log.** `LOG_LEVEL` only sets **gunicorn**'s level. The unified router (`services/logging/router.py:45-53`) writes `error`/`warnings`/`info` streams **regardless of any min-level env** — `info.log` fills continuously. | `router.py` has no min-level filter; prod `.env.example` sets `LOG_LEVEL=warning` but that's gunicorn-only. | "Everything is written → disk fills." There is **no single switch** to make the app log warning-and-above in prod. |
| **G3** | **Gunicorn access log can grow unbounded in the container.** `container/python/gunicorn.conf.py` writes `access.log`/`error.log` to `/app/logs` with **no rotation** (rotation only covers the unified `${VBWD_VAR_DIR}/logs` streams). | `container/python/gunicorn.conf.py:12-14`. | One request line per hit → multi-GB access log over a beta weekend. |
| **G4** | **Duplicate, unused `require_permission`.** `vbwd/decorators/permissions.py:8` defines a second `require_permission` (verify-jwt-in-request flavour) that **no route uses** — name-collides with the live `middleware/auth.py:85` one. | grep: imported in `decorators/__init__.py`, zero route usages. | Confusion/foot-gun: a future author imports the wrong one and gets different (untested) behaviour. Dead-code cleanup (confirm-then-remove). |
| **G5** | **Open endpoints need an authenticity/abuse posture** — `POST /api/v1/webhooks/payment` (`routes/webhooks.py:9`) and the auth routes are public by necessity; confirm webhook **signature validation** and that auth routes are **rate-limited** (the `@limiter` on `/auth` is present — verify the limit is sane for beta, not `5000/min`). | `routes/webhooks.py`, `routes/auth.py`. | Unsigned webhook = forged payment events; loose auth rate-limit = credential-stuffing / DDoS target. |
| **G6** | **No documented dev↔prod switch + no pre-flight verifier.** The knobs exist (`FLASK_ENV`, `VBWD_ENABLE_DEBUG_ENDPOINTS`, `LOG_LEVEL`, the new G2 var) but are scattered; nothing asserts they're set correctly before a deploy. | spread across `config.py`, `app.py`, compose `.env`. | A deploy with `FLASK_ENV` unset → `DevelopmentConfig` → `DEBUG=True`, full tracebacks, dev defaults. Silent, catastrophic. |
| **G7** | **Frontend prod noise (verify).** Plugin `debug_mode` toggles exist per-plugin (fe-admin/fe-user `config.json`/`admin-config.json`), but confirm no unconditional `console.*` / source-maps / verbose logging ship to the public build. | plugin configs; build config. | Info leak + console spam in the beta UI. |

---

## 3. Slices

Ordered so the **durable guard (Slice 1) lands first** and each slice is independently gate-green.

### Slice 1 — Route-exposure oracle (backend, core) — **the keystone**

A test that walks the live `app.url_map` of a fully-booted app (all core + enabled-plugin blueprints) and **classifies every rule**, failing CI on any unclassified exposure. This is the permanent answer to G1 and "are all CRUD endpoints protected?".

**File:** `vbwd-backend/tests/unit/security/test_route_exposure_oracle.py` (+ a small reusable `vbwd/security/route_audit.py` introspection helper so the same logic backs the `prod-readiness` command in Slice 4 — DRY).

**The contract the oracle enforces, per route:**
- A route is **OK** iff one of:
  1. it carries the `requires_auth` marker (set by `@require_auth`), **or**
  2. its rule is in an explicit, reviewed **`PUBLIC_ALLOWLIST`** (auth login/register/logout/forgot/reset, `config/languages`, public `settings/*` reads, public catalog `token-bundles` reads, `webhooks/payment*`, `health`, `ready`, and the `/_routes`+`/_seed_status` debug pair which are gate-protected separately).
- **Mutating routes are stricter:** any rule whose methods include `POST|PUT|PATCH|DELETE` **must** carry `requires_auth` **and** a `required_permission` marker — **unless** it is in a tiny `PUBLIC_MUTATION_ALLOWLIST` (auth + webhooks only). A mutating admin/plugin route without a permission marker **fails**.
- The allowlists live **in the test, version-controlled**, each entry with a one-line justification comment. Adding a public route is a **deliberate, reviewed diff**, not an accident.

**TDD (write first → it goes red on a seeded violation, then green):**
- Boot the app (test app factory, all default plugins enabled); assert **every** rule classifies as OK; the failure message lists each offender as `METHOD /path  (no @require_auth / no permission)` — actionable, like the S29 threshold discipline.
- A **negative fixture**: register a throwaway unprotected `POST /api/v1/_oracle_probe` blueprint in the test → the oracle **fails** naming it (proves the guard actually bites).
- Allowlist entries that no longer exist (stale) → the oracle fails ("allowlisted route not found"), so the allowlist can't rot.
- Assert the two debug routes are present **only** behind `@require_debug_enabled` (marker check), not via the public allowlist.

> **NO OVERENGINEERING:** reuses the existing `requires_auth`/`required_permission` markers and the `/_routes` catalog logic. No new decorator, no global `before_request` rewrite — a **test** is the cheapest correct guard and it can't be bypassed by forgetting to wire middleware.

### Slice 2 — Debug-endpoint & dead-code lockdown (backend, core)

Make the off-by-default state **tested**, and remove the foot-gun.

- **Test the gate:** with `ENABLE_DEBUG_ENDPOINTS` unset/false, `GET /_routes` and `/_seed_status` return **404** (not 403 — existence hidden); with it true, 200. (Characterisation + regression for G-confidence.)
- **Sweep for any other dev-only surface** beyond the known two (introspection, profiling, `/events` echo, anything returning internal state) and either gate it behind `@require_debug_enabled` or document it in the oracle allowlist with justification.
- **G4 cleanup:** confirm `vbwd/decorators/permissions.py`'s `require_permission`/`require_all_permissions`/`require_role` have **zero** route usages (grep + the oracle's marker check), then **remove the dead module** (or, if any are intended future API, add a single live usage + test). **Decision needed from owner** before deletion (it's a public-ish symbol) — flagged in §6.

**TDD:** the 404-when-off / 200-when-on matrix; a guard test that fails if a new ungated debug route appears (the oracle covers this once the route is allowlisted-or-gated).

### Slice 3 — Production log-level switch + bounded logs (backend + ops) — closes G2/G3

The user's headline ops ask: **one file/var controls how much is logged, and logs can't fill the disk.**

- **G2 — app-log min level.** Add a single min-level filter to the unified logging router (`services/logging/`) read once at install from **`VBWD_LOG_LEVEL`** (values `debug|info|warning|error`, default `info` to preserve today's behaviour). At `warning`, the `info` stream stops being written (handler dropped or filtered) — **prod sets `VBWD_LOG_LEVEL=warning`** and `info.log` stops growing. This is **additive + Liskov**: unset/`info` ⇒ identical to today.
  - **TDD:** with `VBWD_LOG_LEVEL=warning`, an `info`-level emit produces **no** `info.log` write while `warning`/`error` still route; unset ⇒ all three streams as today; an invalid value falls back to `info` (no crash).
  - **Documentation deliverable (the user's explicit ask):** a table in the env-switch guide — *"to change how much is logged in production, set `VBWD_LOG_LEVEL` in `vbwd-demo-instances/instances/<name>/.env`"* — plus the rotation knobs `VBWD_LOG_MAX_BYTES`/`VBWD_LOG_BACKUPS`, and which file each stream lands in (`${VBWD_VAR_DIR}/logs/core/{error,warnings,info}.log`).
- **G3 — bound the gunicorn access log.** In the container gunicorn conf, either route access/error to **stdout/stderr** (`-`) so Docker's `json-file` driver + `max-size`/`max-file` rotates them (preferred — set `logging` options in the prod compose), **or** wrap them in a `RotatingFileHandler`. Decide for stdout + compose-level `max-size: 10m, max-file: 5` (DRY with Docker's own rotation, no app code). Document it.
  - **TDD/verify:** a compose-config assertion (the prod compose declares the `logging` driver limits) + a manual note in the report; access-log growth is an ops property, proven by the compose config, not a unit test.

### Slice 4 — `flask prod-readiness` command + RC-1 pre-rollout checklist (backend + docs) — closes G6

A single command that a release manager (or CI deploy step) runs to assert the instance is production-safe. It reuses the `route_audit.py` helper (Slice 1) and reads the live config.

**Command:** `flask prod-readiness` (in `vbwd/cli/`), exit 0 only if **all** checks pass; prints a checklist with ✅/❌ per item and a non-zero exit + summary on any ❌.

**Automated checks (each a unit test + a line in the command):**
1. `FLASK_ENV == production` and the active config is `ProductionConfig` (`DEBUG is False`).
2. `FLASK_SECRET_KEY` / `JWT_SECRET_KEY` are **not** the dev defaults (ProductionConfig already enforces at boot — here it's an explicit green tick).
3. `ENABLE_DEBUG_ENDPOINTS` is **falsy** → `/_routes` + `/_seed_status` are 404.
4. `VBWD_LOG_LEVEL` is `warning` or `error` (warn if `info`/`debug` in prod).
5. The **route-exposure oracle passes** against the live url_map (no unprotected route).
6. No **load-test / demo seed** markers present in prod tables (reuse the `loadtest-`/demo-slug detection from S89 / seed status) — warn, don't hard-fail.
7. Error responses **don't leak tracebacks** (`DEBUG False` ⇒ generic 500; assert the registered error handlers return sanitized bodies).
8. CORS / allowed origins are not `*` in prod (verify the config).

**The written RC-1 checklist** (`docs/dev_log/20260613/reports/NN-s90-rc1-pre-rollout-checklist.md`, also linked from a stable `docs/ops/rc1-pre-rollout-checklist.md`): the automated items above **plus** the manual ones — DB migrations at head, backups configured, secrets rotated, nginx `client_max_body_size`/timeouts sane (cross-ref S89 findings), rate-limits reviewed (G5), frontend prod build has no source-maps/`console` noise (Slice 5), TLS/HSTS, and "tag modules RC-1" sign-off. Each item: *what to check · how to verify · pass criterion*.

**TDD:** `prod-readiness` returns 0 on a correctly-configured prod app fixture and non-zero (naming the failing item) on a fixture with each gap injected (debug on, dev secret, info log level, an unprotected route).

### Slice 5 — Frontend prod-noise audit + env-switch screenshots (fe-admin / fe-user + docs) — closes G7, finishes G6 docs

- **Verify** the public production build emits **no** unconditional `console.*` and **no source-maps**; if any plugin logs unconditionally, gate it behind that plugin's existing `debug_mode` flag (the established per-plugin toggle). Add a lightweight lint/build assertion where cheap; otherwise a documented manual check.
- **Screenshots (the user's explicit ask):** the env-switch guide (`docs/ops/dev-prod-environment-switch.md`) includes screenshots of (a) the fe-admin **plugin settings page** showing a `debug_mode` toggle, and (b) the prod `.env` / compose stanza that sets `FLASK_ENV=production`, `VBWD_ENABLE_DEBUG_ENDPOINTS` unset, `VBWD_LOG_LEVEL=warning`, and the Docker `logging` rotation limits — so an operator can see exactly **which file configures the log level and the dev/prod mode.**
- **G5 verify:** confirm `POST /webhooks/payment` validates a provider signature before acting; tighten the `/auth` rate-limit to a beta-appropriate value (document the chosen number).

---

## 4. The "where is it configured?" reference (deliverable in the guide)

A single table the user explicitly asked for — *which file/var controls each prod toggle*:

| Concern | Lever | Where it's set (prod) | Default | Prod value |
|---|---|---|---|---|
| Debug vs prod mode | `FLASK_ENV` → config class | `instances/<name>/.env` | `development` | `production` |
| Flask debug / tracebacks | `DEBUG` (via config class) | derived from `FLASK_ENV` | `True` (dev) | `False` |
| Dev/debug endpoints | `VBWD_ENABLE_DEBUG_ENDPOINTS` | `instances/<name>/.env` | off | **unset/off** |
| **App log verbosity** (NEW, G2) | `VBWD_LOG_LEVEL` | `instances/<name>/.env` | `info` | `warning` |
| Gunicorn log level | `LOG_LEVEL` | `instances/<name>/.env` | `info` | `warning` |
| Log file size / retention | `VBWD_LOG_MAX_BYTES` / `VBWD_LOG_BACKUPS` | `instances/<name>/.env` | 10 MiB / 5 | tuned |
| Access-log rotation (NEW, G3) | Docker `logging` driver `max-size`/`max-file` | `instances/<name>/docker-compose.yml` | unbounded | 10m / 5 |
| Log file locations | `VBWD_VAR_DIR` | `instances/<name>/.env` | `/app/var` | `/app/var` (mounted volume) |
| Per-plugin debug logging | plugin `debug_mode` | fe-admin plugin settings UI / plugin `config.json` | `false` | `false` |

---

## 5. Out of scope (named, so it's a choice)

- **A global `before_request` auth guard / "deny by default" router.** Considered for G1; rejected as overengineering — the **oracle** gives the same guarantee (no unprotected route ships) without changing every public route's flow or risking a blanket-403 regression. Revisit only if the per-route model proves leaky despite the oracle.
- **A full pentest / dependency-CVE sweep / WAF.** This sprint hardens *our* exposures and config; a third-party security review is a separate, later engagement (the RC-1 checklist links it as a manual pre-GA item).
- **Rewriting the legacy logging or moving to a log-shipping stack (ELK/Loki).** Out of scope; we add the **min-level switch + rotation** so disk is bounded. Centralised logging is a post-beta ops decision.
- **Rate-limiting infrastructure beyond the existing `flask-limiter`** (e.g. per-tenant quotas, distributed limits). We *tune* the existing limits (G5); a new system is separate.
- **nginx body-size / proxy-timeout tuning** — surfaced and cross-referenced from S89; raising prod limits is its own reviewed change.
- **fe code-splitting / CSP headers** beyond removing console noise + source-maps — CSP/security-headers can be a fast follow.

---

## 6. Acceptance / Definition of Done

1. `bin/pre-commit-check.sh --full` green on `vbwd-backend`; **route-exposure oracle green**; the negative fixture proves it bites. No new lint suppressions ([[feedback_no_noqa_without_permission]]).
2. `flask prod-readiness` exits **0** against a `ProductionConfig` app booted with the documented prod `.env`, and exits **non-zero naming the item** for each injected gap (debug-on, dev secret, `info` log level, an unprotected route). Unit-tested both ways.
3. The debug-endpoint gate matrix is tested (404 off / 200 on) and `VBWD_ENABLE_DEBUG_ENDPOINTS` documented as default-off.
4. **G2 done:** `VBWD_LOG_LEVEL=warning` demonstrably stops `info.log` writes (unit-tested); unset ⇒ behaviour identical to today; the env-switch guide documents the var + the log-file locations.
5. **G3 done:** the prod compose declares Docker `logging` rotation limits (or gunicorn rotates); access log can't grow unbounded — proven by the compose config.
6. **G4 resolved** per owner decision (§ below): the duplicate `require_permission` module is removed (confirmed-unused) or given a live usage + test.
7. **G5 verified:** payment webhook signature-validated; `/auth` rate-limit set to a documented beta value.
8. **G7 verified:** prod frontend build has no source-maps and no unconditional `console.*`; any plugin logging rides its `debug_mode`.
9. **Deliverable docs:** `docs/ops/dev-prod-environment-switch.md` (with the §4 table + screenshots of the fe-admin `debug_mode` toggle and the prod `.env`/compose) and `docs/ops/rc1-pre-rollout-checklist.md` (the automated `prod-readiness` items + the manual ones), both linked from the completion report.
10. Completion report `docs/dev_log/20260613/reports/NN-s90-close-all-exposures.md` with: the full audited route table (public-allowlisted vs protected), each gap G1–G7 with its as-built fix, and the green `prod-readiness` run output.

---

## 7. Decisions to confirm (owner) + risks

**Decisions needed before/within the sprint:**
- **D1 — `VBWD_LOG_LEVEL` default.** Keep `info` (preserve today; prod opts down to `warning`) vs default `warning` everywhere (quieter, but changes dev behaviour). **Recommend `info` default, prod sets `warning`** — least surprise, explicit prod intent.
- **D2 — G4 dead-code.** Confirm `vbwd/decorators/permissions.py` (`require_permission`/`require_all_permissions`/`require_role`/`require_feature`/`check_usage_limit`) is removable. **Note:** `require_feature`/`check_usage_limit` may be intended entitlement hooks — likely **keep those, remove only the JWT-flavour `require_permission`/`require_role` that collide + are unused.** Owner to confirm before deletion.
- **D3 — access-log strategy (G3).** Docker `logging` driver limits (recommended, zero app code) vs a `RotatingFileHandler` in gunicorn conf.
- **D4 — `/auth` rate-limit value** for public beta (the current `5000/min` is effectively unlimited).

**Risks:**
- **Oracle false-positives on plugin routes.** Some plugin blueprints may use plugin-local auth wrappers that don't stamp the core marker. Mitigation: the oracle accepts **any** recognised auth marker; plugins missing one get a marker-shim (cheap) or an allowlist entry with justification — surfaced as findings, not silent passes.
- **Log-level filter interacting with the audit `events.log`.** The audit/event stream must **not** be suppressed by `VBWD_LOG_LEVEL` (it's a security record, not verbosity). The filter applies only to the `info`/`warnings`/`error` app streams; `events.log` is exempt by design — tested.
- **Disabling debug endpoints in an environment that relied on them** (e.g. the S29/S89 load harness uses `/_routes` + `/_seed_status` pre-flight). Mitigation: those run with `VBWD_ENABLE_DEBUG_ENDPOINTS=1` set explicitly by the harness — prod leaves it unset. Documented in the checklist.

## 8. Cross-references
- S30 load-test affordances (`/_routes`, `/_seed_status`) — the gated endpoints this sprint asserts stay off in prod.
- [S89 heavy-load data-exchange](s89-heavy-load-data-exchange.md) — nginx `client_max_body_size` / 60s admin-proxy-cut findings feed the RC-1 checklist's ops items.
- [[feedback_no_noqa_without_permission]] · [[feedback_no_direct_db_for_test_data]] · [[feedback_migrations_only]] · [[project_fe_admin_plugin_runtime_manifests]] (the 60s admin nginx cut) · [[feedback_never_mix_local_and_prod_compose]] (prod compose edits land only in `instances/<name>/`, never local).
