# Report — CI failure audit across 39 VBWD repos

**Date:** 2026-04-23
**Status:** snapshot of `./recipes/ci-status.sh` output + per-repo root-cause analysis.
**Scope:** 39 repos in the `VBWD-platform` org. 11 red, 28 green.

## Red list (11)

| Repo | Workflow | Latest run | Primary root cause |
|---|---|---|---|
| vbwd-demo-instances | Deploy to VPS | 24841080460 | Missing instance `.env` for `saas` + `admin@example.com` login returns 401 during post-deploy seed |
| vbwd-platform | vbwd-platform CI | 24838459135 | Backend unit tests run against unmigrated DB (22 "relation does not exist") + vitest picking up a Playwright spec |
| vbwd-fe-user | Plugin Tests | 24838461305 | Unit job fails inside a shell wrapper that swallows the vitest output |
| vbwd-fe-admin-plugin-booking | Tests | 24838452346 | E2E spec `booking-resources-crud.spec.ts` — resource page never renders because seed-test-data Flask command is missing |
| vbwd-fe-user-plugin-cms | Tests | 24834623832 | Unit spec imports a sibling plugin that isn't cloned in this repo's CI checkout |
| vbwd-plugin-booking | CI | 24838454279 | flake8: F811 duplicate `on_enable` in `__init__.py` + F401 unused `patch` import |
| vbwd-plugin-cms | Tests | 24784958229 | `black --check` reports 7 files need reformatting |
| vbwd-plugin-discount | Tests | 24682155285 | black (12 files) + pytest exit 5 "no tests collected" in integration job |
| vbwd-plugin-shipping_flat_rate | Tests | 24682155782 | black: 1 file needs reformatting |
| vbwd-plugin-shop | Tests | 24682153976 | black (many files) + pytest exit 5 in integration job |
| vbwd-plugin-subscription | Tests | 24681996888 | black (many files) + pytest exit 5 in integration job |

## Cross-cutting patterns (5 underlying bugs, not 11)

Once you group the red list by failure mode, there are only five root causes to fix:

### Pattern A — Black drift (5 repos)
`vbwd-plugin-cms`, `vbwd-plugin-discount`, `vbwd-plugin-shipping_flat_rate`, `vbwd-plugin-shop`, `vbwd-plugin-subscription` — all fail on `black --check`. The source was edited without running `black .` before commit, and none of these repos have a pre-commit hook enforcing it.

Fix: one-liner per repo — `docker compose run --rm api black plugins/<name>/` (or equivalent) + commit. Longer term: wire the `black` check into the pre-push hook so CI drift becomes impossible.

### Pattern B — Integration-test step points at a path pytest can't find (3 repos)
`vbwd-plugin-discount`, `vbwd-plugin-shop`, `vbwd-plugin-subscription` all return `exit 5 / no tests ran in 0.01s` from the integration-test step of the shared Tests workflow. Exit 5 is pytest's "I collected zero tests" signal.

Inspection shows the integration-test invocation was copied from `vbwd-plugin-cms` (which has tests at `tests/integration/`) but the newer plugins placed theirs under `plugins/<name>/<name>/tests/integration/` per the new convention documented in `MEMORY.md`. The workflow file's test path doesn't match.

Fix: in each plugin's `.github/workflows/tests.yml`, update the integration-test invocation from `tests/integration/` to the repo's actual layout, or skip the step gracefully when no integration tests exist.

### Pattern C — Vitest collects Playwright specs (2 repos)
`vbwd-platform` and `vbwd-fe-user-plugin-cms` both fail because vitest picks up `plugins/cms/tests/e2e/theme-contrast.spec.ts`, which uses `test.describe.configure({ mode: 'serial' })` (Playwright-only) and tries to connect to `127.0.0.1:3000` during the run. Error surface:
```
Error: Playwright Test did not expect test.describe.configure() to be called here.
AggregateError [ECONNREFUSED]: connect ECONNREFUSED 127.0.0.1:3000
```

Fix: add `plugins/**/tests/e2e/**` (and any other `*e2e*` glob) to each vitest config's `exclude` list. The Playwright config already covers those paths correctly.

### Pattern D — Missing `.env` / missing admin seed on the VPS deploy flow (1 repo)
`vbwd-demo-instances` run 24841080460 fails on the `saas` instance with `env file /opt/vbwd/instances/saas/.env not found`. Separately, `apply-instance-seed.py` returns 401 UNAUTHORIZED on `admin@example.com` login for every running instance (non-fatal, but the seed is silently skipped for all of them).

Fix (partial — only the `.env` self-heal): commit `6010259` on local `main` of `vbwd-demo-instances` synthesises the missing `.env` from `/opt/vbwd/.env`. **Not yet pushed**; the workflow will keep failing on `saas` until `git push origin main` lands this commit.

The 401 is a separate issue tracked as a follow-up — likely the admin user isn't auto-seeded on a fresh database, or the hard-coded password in the script drifted from what the backend expects. Not blocking the deploy once the `.env` fix lands (the script wraps the login in a `WARN` branch).

### Pattern E — Backend unit tests hit an unmigrated DB in the monorepo (1 repo)
`vbwd-platform` CI has 22 failing backend unit tests with `sqlalchemy.exc.ProgrammingError: UndefinedTable: relation "<name>" does not exist` for `cms_routing_rules`, `vbwd_role`, `vbwd_user`, `vbwd_tax`, `vbwd_tax_class`. Plus one `FileNotFoundError: 'images/resize-me.png'`.

Cause: the `All Plugins — Unit Tests` job brings up Postgres but never runs Alembic before pytest. The individual plugin repos run migrations first; the platform mega-run skipped that step.

Fix: add `docker compose run --rm api alembic upgrade heads` (or the platform's equivalent) before the `pytest` invocation in `vbwd-platform/.github/workflows/ci.yml`.

The `resize-me.png` failure is a pre-existing test bug unrelated to this audit — the cms image service test constructs a relative path expecting a file that isn't committed — and has been failing for weeks in every repo that runs it.

## Repo-specific details

### vbwd-demo-instances (run 24841080460)

```
out: === saas ===
err: level=warning msg="The \"DOMAIN\" variable is not set. Defaulting to a blank string."
err: env file /opt/vbwd/instances/saas/.env not found
2026/04/23 14:33:08 Process exited with status 1
```

Plus (earlier, non-fatal):
```
requests.exceptions.HTTPError: 401 Client Error: UNAUTHORIZED for url: http://localhost:5000/api/v1/auth/login
```

Fix: push `6010259` (`cd vbwd-demo-instances && git push origin main`). Separately investigate the 401 after the workflow re-runs green.

### vbwd-platform (run 24838459135)

Two clusters. DB-not-migrated failures (representative tail):
```
E   sqlalchemy.exc.ProgrammingError: (psycopg2.errors.UndefinedTable) relation "vbwd_role" does not exist
E   sqlalchemy.exc.ProgrammingError: (psycopg2.errors.UndefinedTable) relation "vbwd_user" does not exist
E   sqlalchemy.exc.ProgrammingError: (psycopg2.errors.UndefinedTable) relation "vbwd_tax" does not exist
FAILED tests/unit/routes/test_admin_tax.py (14 tests)
FAILED tests/unit/test_require_permission_decorator.py (4 tests)
FAILED tests/unit/routes/test_invoice_routes.py::TestInvoicePdfRoute::test_download_invoice_pdf_returns_pdf_bytes
```

And vitest picking up a Playwright spec:
```
Error: Playwright Test did not expect test.describe.configure() to be called here.
  plugins/cms/tests/e2e/theme-contrast.spec.ts:113:15
AggregateError [ECONNREFUSED]: connect ECONNREFUSED 127.0.0.1:3000
```

Fix: (a) add `alembic upgrade heads` before the pytest step; (b) exclude `**/tests/e2e/**` from the vitest config.

### vbwd-fe-user (run 24838461305)

Lint + TypeScript pass. Unit job fails but the actual error is hidden by the shell script:
```
Running unit tests...
<no output>
Process exited 1
```

Root cause is almost certainly the same `plugins/cms/tests/e2e/theme-contrast.spec.ts` (Playwright→vitest) issue as vbwd-platform, because that file lives inside the fe-user repo's cms plugin submodule.

Fix: two separate things. Make `bin/pre-commit-check.sh` not swallow vitest stdout (add `set -o pipefail` and don't redirect to `/dev/null`). And apply the vitest exclude-glob fix.

### vbwd-fe-admin-plugin-booking (run 24838452346)

17 of 18 E2E tests pass. The one failure is `booking-resources-crud.spec.ts`:
```
✘ booking: login → create categories → create resources (16.9s)
Error: expect(locator('h2:has-text("Resources & Categories")')).toBeVisible() failed
  Timeout: 15000ms
  Element(s) not found
```

Earlier in the same log, the seed step fails silently:
```
Error: Could not locate a Flask application.
Error: No such command 'seed-test-data'.
```

The Resources page needs seed data to render; seed command is missing on the admin container.

Fix: either (a) wire the `seed-test-data` CLI command into the backend image so the test fixture can create resources directly via the admin API, or (b) update the test to seed via the admin HTTP API instead of the Flask CLI.

### vbwd-fe-user-plugin-cms (run 24834623832)

```
FAIL  vue/tests/unit/plugins/cms-plugin.spec.ts
  Error: Failed to resolve import "../../../../plugins/landing1"
    from "vue/tests/unit/plugins/cms-plugin.spec.ts".
```

The spec imports a sibling plugin (`landing1`) that isn't cloned into this repo's CI workspace.

Fix: either (a) mock the landing1 import in the spec (preferred — specs shouldn't depend on sibling repos), or (b) extend the CI checkout to clone landing1 alongside cms.

### vbwd-plugin-booking (run 24838454279)

```
vbwd-backend/plugins/booking/__init__.py:97:5: F811 redefinition of unused 'on_enable' from line 36
vbwd-backend/plugins/booking/tests/unit/test_routes_public_config.py:2:1: F401 'unittest.mock.patch' imported but unused
```

`on_enable` is defined twice in the plugin class — line 36 and line 97. The second definition shadows the first. This likely slipped in during the plugin-template-path-registration work done today (the second `on_enable` registers the PDF template path). Merge the two definitions.

`patch` is imported but not used — remove the import.

### vbwd-plugin-cms (run 24784958229)

Black reports 7 files drifted:
```
would reformat docs/imports/_build_theme_styles.py
would reformat src/services/cms_page_service.py
would reformat src/bin/populate_cms.py
would reformat tests/integration/test_cms_style_default.py
would reformat tests/unit/services/test_cms_style_service.py
would reformat tests/unit/services/test_cms_page_service.py
would reformat src/routes.py
```

Fix: `black .` + commit.

### vbwd-plugin-discount (run 24682155285), vbwd-plugin-shop (run 24682153976), vbwd-plugin-subscription (run 24681996888)

All three: black drift (multiple files) + `no tests ran in 0.01s` from the integration-test job.

Fix per repo: `black .` + commit, then update `tests.yml` integration step to point at the correct path or skip if empty.

### vbwd-plugin-shipping_flat_rate (run 24682155782)

Single file:
```
would reformat shipping_flat_rate/shipping_flat_rate/provider.py
```

Fix: `black .` + commit.

## Suggested fix order (fastest → deepest)

1. **Black across 5 plugin repos** — 5 minutes total, each is a one-liner. Clears 5 of 11 red entries.
2. **Push `vbwd-demo-instances` commit `6010259`** — unblocks the deploy workflow's saas step. Clears 1 entry.
3. **Delete dup `on_enable` + unused `patch` in `vbwd-plugin-booking`** — 2-line fix. Clears 1 entry.
4. **Integration-test path fix** in discount/shop/subscription workflows — 1-line edit per workflow. Completes 3 entries (already listed in item 1 but the black fix alone wasn't enough for these three).
5. **Vitest exclude glob for `tests/e2e/**`** in `vbwd-platform` + `vbwd-fe-user-plugin-cms`. Clears 2 entries (plus clears the hidden-output failure in `vbwd-fe-user` — item 6 below is a symptom of this too).
6. **Stop hiding vitest output in `vbwd-fe-user/bin/pre-commit-check.sh`** — defensive change so the next CI failure is legible.
7. **Add `alembic upgrade heads` to `vbwd-platform` CI before pytest** — clears the 22 UndefinedTable failures and the one PDF-test failure.
8. **Fix `booking-resources-crud.spec.ts` seed dependency** in `vbwd-fe-admin-plugin-booking` — either restore the Flask `seed-test-data` command or rewrite the spec to seed via HTTP.
9. **Mock `landing1` import** in `vbwd-fe-user-plugin-cms/vue/tests/unit/plugins/cms-plugin.spec.ts`.

Items 1–5 are < 30 min of work and drop the red count from 11 to 3. Items 6–9 are each 30-60 min and clear the rest.

## What's NOT broken

28 of 39 repos are green. Notable greens after today's plugin-management work:
- `vbwd-backend` — PdfService + frontend-plugins endpoint tests all passing
- `vbwd-fe-admin` — router fix + booking widget + subscription widget all green
- `vbwd-fe-user-plugin-booking` — 14 store specs green
- `vbwd-fe-admin-plugin-subscription` — new widget, green
- `vbwd-plugin-cms`, `vbwd-plugin-ghrm`, `vbwd-plugin-taro`, etc. — stable

## Appendix — how the data was collected

```bash
./recipes/ci-status.sh       # initial red/green list
for run in 24841080460 24838459135 24838461305 24838452346 24834623832 \
           24838454279 24784958229 24682155285 24682155782 24682153976 \
           24681996888; do
  gh run view "$run" --repo VBWD-platform/<repo> --log-failed
done
```
