# Sprints — 2026-05-14 — CI Recovery for 3 Failing Plugins

**Trigger:** `./recipes/ci-status.sh` reported three failed CI runs on `main`:

| Repo | Last status | Last run | Root cause (from GH Actions log) |
| --- | --- | --- | --- |
| `vbwd-plugin-shipping_flat_rate` | `completed/failure` | 2026-04-20 (run 24682155782) | Black formatter check failed — `provider.py` line 35–37 needs single-line `sum(... for ...)` |
| `vbwd-plugin-shop`               | `completed/failure` | 2026-05-05 (run 25366542159) | Step "Run integration tests" → `pytest plugins/shop/tests/integration/` collected 0 items → exit 5 (empty `integration/` dir guarded only by `[ -d ]`) |
| `vbwd-plugin-subscription`       | `completed/failure` | 2026-05-10 (run 25628978013) | Same as shop — empty `tests/integration/` dir → exit 5 |

**Working directory rule (per `feedback_work_in_sdk_dirs.md` in MEMORY):**
all three plugin repos are cloned at:
- `vbwd-backend/plugins/shipping_flat_rate/` (origin → `VBWD-platform/vbwd-plugin-shipping_flat_rate`)
- `vbwd-backend/plugins/shop/` (origin → `VBWD-platform/vbwd-plugin-shop`)
- `vbwd-backend/plugins/subscription/` (origin → `VBWD-platform/vbwd-plugin-subscription`)

Work directly in those checkouts (PyCharm-synced, no `/tmp` copies). Each fix is committed and pushed to `main` of the standalone plugin repo (per `feedback_no_temp_branches.md`).

**Local verification gate (every sprint):**

```bash
cd vbwd-backend
./bin/pre-commit-check.sh --plugin shipping_flat_rate --quick
./bin/pre-commit-check.sh --plugin shop                --quick
./bin/pre-commit-check.sh --plugin subscription        --quick
```

`--quick` runs lint + unit (skips integration). Each must exit `0` before the corresponding sprint commits anything. After all three are green locally we push and re-run `./recipes/ci-status.sh` to confirm GitHub Actions agrees.

## Sprint index

| # | Sprint | Failure class | Effort |
| --- | --- | --- | --- |
| [01](./01-shipping-flat-rate-ci-fix.md) | shipping_flat_rate — Black format gate | Style | XS (single file) |
| [02](./02-shop-ci-fix.md)               | shop — collect-0 in empty `integration/` | CI guard + smoke integration test | S |
| [03](./03-subscription-ci-fix.md)       | subscription — collect-0 in empty `integration/` | CI guard + smoke integration test | S |
| [04](./04-shared-ci-pytest-no-collect-guard.md) | shared workflow hardening | DRY: stop pytest exit-5 from breaking every plugin CI | S |

## Engineering requirements (binding for every sprint here)

Inlined from [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md). Highlights that this batch of CI-fix sprints leans on:

- **TDD-first** — every fix is preceded by a failing test (or a failing local `pre-commit-check.sh` run captured in the sprint). No "fix and hope".
- **DRY** — the CI guard added to fix shop is reused verbatim in subscription; we factor the pattern into sprint 04 so every plugin repo gets the same `[ -d ] && [ -n "$(find ... -name 'test_*.py')" ]` guard.
- **SOLID** — sprint 02/03 changes touch the workflow YAML (single responsibility: "run integration tests if and only if any exist"); they do not add or modify production code, keeping the fix scoped.
- **Clean code** — variables in any new shell snippet use full, readable names per `feedback_variable_naming.md` (`integration_dir`, `integration_test_count`, not `d`, `n`).
- **No `# noqa` / `# type: ignore`** — `feedback_no_noqa_without_permission.md`. Black is the source of truth; if a line is ugly, restructure it.
- **No commit without ask** for `pitchmacher-vbwd` (not relevant here — these are plugin repos), but the *broader* habit of "show diff, get confirmation, then push" applies to each plugin push too.
- **Standalone repos only** — every commit lands directly on `main` of the relevant `vbwd-plugin-*` repo. No temp branches, no PRs to core.
