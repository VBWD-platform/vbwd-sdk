# Report 13 — Plugin Repositories CI & GitHub Org Finalisation

**Date:** 2026-03-16
**Scope:** Standalone plugin repos, GitHub Actions CI, monorepo workflow updates, org migration completion

---

## Summary

Completed the VBWD-platform GitHub organisation setup by wiring all 25 standalone plugin repositories with local git repos, GitHub Actions CI pipelines, and push tooling. Also finalised all dantweb → VBWD-platform URL migrations across installation scripts and READMEs.

---

## 1. Monorepo CI — Plugin Test Workflows

Added `plugin-tests.yml` to the `.github/workflows/` of the three core repos, running all plugin tests in a matrix on every push:

| Repo | Workflow | Matrix |
|------|----------|--------|
| `vbwd-backend` | `plugin-tests.yml` | 10 backend plugins (unit + integration) |
| `vbwd-fe-user` | `plugin-tests.yml` | 10 fe-user plugins |
| `vbwd-fe-admin` | `plugin-tests.yml` | 5 fe-admin plugins |

All three committed and pushed to VBWD-platform.

---

## 2. Standalone Plugin Repos — CI Workflows

### `setup-plugin-ci.sh`

Upgraded script at `recipes/setup-plugin-ci.sh`. Now does two things per plugin in one pass:

1. **Writes** `.github/workflows/tests.yml` locally inside the plugin directory
2. **Syncs** it to the corresponding VBWD-platform GitHub repo via `gh api PUT`

Idempotent — fetches existing file SHA before updating, safe to re-run.

### Backend plugin CI pipeline (single job: `ci`)

Steps executed sequentially in one job:

| # | Step | Detail |
|---|------|--------|
| 1 | Clone vbwd-backend | `actions/checkout@v4 → vbwd-backend/` |
| 2 | Clone plugin | `actions/checkout@v4 → vbwd-backend/plugins/<name>/` |
| 3 | Style — Black | `black --check --diff` on plugin directory |
| 4 | Style — Flake8 | `flake8 --max-line-length=120 --extend-ignore=E203,W503` |
| 5 | Style — Mypy | `mypy src/ --ignore-missing-imports`; skips if no `src/` |
| 6 | Start stack | `docker compose up -d --build` + API health poll (30 × 3 s) |
| 7 | Enable plugin | `docker compose exec -T api flask plugins enable <name>` |
| 8 | Unit tests | `docker compose --profile test run --rm -T test pytest` + JUnit XML |
| 9 | Integration tests | `if: always()` — same container, `tests/integration/` only |
| 10 | Upload artifacts | `actions/upload-artifact@v4`, 14-day retention, keyed by run number |
| 11 | Cleanup | `if: always()` — `docker compose down -v` |

**Root cause fix (DATABASE_URL):** The plugin conftest's `_test_db_url()` always appends `_test` to the DB name. Previous workflows used `DATABASE_URL=.../vbwd_test`, resulting in `vbwd_test_test` (non-existent). Fixed by setting `DATABASE_URL=.../vbwd` so the conftest correctly generates `vbwd_test`.

### Frontend plugin CI (fe-user / fe-admin)

Single `test` job: checkout parent app with submodules → overlay plugin → build vbwd-fe-core → npm install → `vitest run plugins/<name>`. Skips gracefully if no `.spec.ts` files found.

---

## 3. Local Plugin Git Repos

Each of the 25 plugin directories now has an independent git repo initialized with the correct VBWD-platform remote:

| Group | Count | Remote pattern |
|-------|-------|---------------|
| Backend | 10 | `github.com/VBWD-platform/vbwd-plugin-<name>` |
| fe-user | 10 | `github.com/VBWD-platform/vbwd-fe-user-plugin-<name>` |
| fe-admin | 5 | `github.com/VBWD-platform/vbwd-fe-admin-plugin-<name>` |

`.gitignore` added to all 25 (excludes `__pycache__/`, `*.pyc`, `node_modules/`, `dist/`).

`gh auth setup-git` configured to resolve 403 push errors for the VBWD-platform org.

---

## 4. `push-plugins.sh`

New script at `recipes/push-plugins.sh`. For each plugin:
- `git add -A` (respects `.gitignore`)
- `git commit` if anything staged
- `git push -u origin main --force` (force needed: remote has only auto-generated README commit)

Supports targeting a single plugin:
```bash
./recipes/push-plugins.sh ghrm
./recipes/push-plugins.sh fe-user chat
./recipes/push-plugins.sh fe-admin email-admin
```

`analytics` backend plugin already pushed (force-push verified auth works).

---

## 5. Installation Scripts & README Updates

| File | Change |
|------|--------|
| `recipes/dev-install-ce.sh` | All 4 repo URLs `dantweb` → `VBWD-platform` |
| `vbwd-backend/README.md` | Clone URL + Plugin Directory table (10 repos) |
| `vbwd-fe-user/README.md` | Clone URL + Plugin Directory table (10 repos) |
| `vbwd-fe-admin/README.md` | Clone URL + Plugin Directory table (5 repos) |

---

## 6. CI Status Script

`recipes/ci-status.sh` — queries the latest GitHub Actions run for every VBWD-platform repo and prints a formatted table. Uses `gh api` with `--jq` for compact output.

```
REPO                                           STATUS/CONCLUSION       BRANCH           DATE
----                                           -----------------       ------           ----
vbwd-backend                                   completed/success       main             2026-03-16
vbwd-fe-admin-plugin-analytics-widget          completed/success       main             2026-03-16
vbwd-plugin-ghrm                               completed/failure       main             2026-03-16
...
```

Browser equivalent: `https://github.com/orgs/VBWD-platform/actions`

---

## 7. Current CI Status (2026-03-16)

| Group | Status | Notes |
|-------|--------|-------|
| `vbwd-backend` | ✅ success | |
| `vbwd-fe-core` | ✅ success | |
| `vbwd-fe-user` | ❌ failure | To investigate |
| `vbwd-fe-admin` | ❌ failure | To investigate |
| All fe-user plugin repos | ✅ success | Workflow-only repos pass (no source to test) |
| All fe-admin plugin repos | ✅ success | Same |
| All 10 backend plugin repos | ❌ failure | Expected — source not yet pushed via `push-plugins.sh` |

---

## Recipes Summary

| Script | Purpose |
|--------|---------|
| `recipes/setup-plugin-ci.sh` | Write + sync `.github/workflows/tests.yml` for all 25 plugin repos |
| `recipes/push-plugins.sh` | Push plugin source to standalone VBWD-platform repos |
| `recipes/ci-status.sh` | Print latest CI run status for every VBWD-platform repo |
| `recipes/dev-install-ce.sh` | Full CE install (now points to VBWD-platform) |
