# Sprint 01 — `vbwd-plugin-shipping_flat_rate` CI Recovery

**Status:** PLANNED — 2026-05-14
**Repo:** `VBWD-platform/vbwd-plugin-shipping_flat_rate` (cloned at `vbwd-backend/plugins/shipping_flat_rate/`)
**Last failed run:** [25366*… 24682155782 — 2026-04-20](https://github.com/VBWD-platform/vbwd-plugin-shipping_flat_rate/actions/runs/24682155782)
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding.

---

## 1. Failure analysis (root cause, not symptom)

The CI job `CI — shipping_flat_rate` failed at step **"Style check — Black"** with exit code `1`. The full failing diff from the run log:

```diff
--- vbwd-backend/plugins/shipping_flat_rate/shipping_flat_rate/provider.py  2026-04-20 18:00:40+00:00
+++ vbwd-backend/plugins/shipping_flat_rate/shipping_flat_rate/provider.py  2026-04-20 18:01:02+00:00
@@ -30,13 +30,11 @@
         is_domestic = country in domestic_countries

         # Check free shipping threshold
-        cart_total = sum(
-            Decimal(str(item.get("total_price", 0))) for item in items
-        )
+        cart_total = sum(Decimal(str(item.get("total_price", 0))) for item in items)
         free_above = Decimal(str(self._config.get("free_shipping_above", 0)))
```

Black reports: `1 file would be reformatted, 5 files would be left unchanged`. Subsequent steps (Flake8, Mypy, unit tests, integration tests) never ran because the workflow has `set -e` semantics on the first non-zero exit.

The other 5 plugin Python files are already Black-clean. So this is a **single-file, single-hunk** style regression introduced by an editor that re-wrapped the `sum(...)` call.

**Why Black wants the one-liner:** the expression fits in 88 chars (Black's default line length). Black's policy is "prefer one line when it fits" — the previous multi-line form was a magic-trailing-comma artifact that Black rejects when the trailing comma is absent.

**Why CI did not auto-recover:** Black runs in `--check --diff` mode in `tests.yml` line 41–43; there is no auto-format push step. That is correct policy — formatting drift must be fixed by the author, not by CI.

## 2. Scope

**In:** Reformat the single offending hunk in `shipping_flat_rate/provider.py`. Verify locally with the project's standard pre-commit gate. Push to `main`.

**Out:** No behavior changes. No new tests (the existing `tests/unit/test_provider.py` already covers `calculate_rate`). No CI workflow changes — sprint 04 handles workflow hardening centrally.

## 3. TDD checkpoints (red → green → refactor)

Even for a one-line style fix we keep the discipline:

1. **Red — reproduce locally before touching code.**
   ```bash
   cd vbwd-backend
   ./bin/pre-commit-check.sh --plugin shipping_flat_rate --lint
   ```
   Expected: exit code `1` from Black with the same diff the CI run printed. Capture the output verbatim into the sprint report (sprint 04 needs this baseline). If Black is *already* clean locally, stop — the failure is environmental and the sprint pivots to investigating editor config.

2. **Behavior preservation test (must be green both before and after).**
   ```bash
   docker compose run --rm test pytest plugins/shipping_flat_rate/tests/unit/ -v
   ```
   Records the exact set of test_provider.py cases passing today. After the format fix, the same set must still pass — proves Black's reflow is behavior-neutral.

3. **Green — apply Black to the one file.**
   ```bash
   docker compose run --rm test black plugins/shipping_flat_rate/shipping_flat_rate/provider.py
   ```
   Why scoped to the one file: Black on the whole tree is wider-blast-radius than the failure justifies. Sprint 04 will run a project-wide Black audit; we do not preempt that here.

4. **Re-run the full local gate.**
   ```bash
   ./bin/pre-commit-check.sh --plugin shipping_flat_rate --quick
   ```
   Must exit `0`. If Flake8 or Mypy find latent issues, log them — but do **not** silently fix in this sprint (scope creep). Open follow-up sprint instead.

## 4. SOLID / DRY / clean code applied

- **SRP:** `provider.py` already has a single responsibility (compute shipping rate). The reformat does not change that.
- **OCP:** The `IShippingProvider` interface is untouched, so other shipping plugins (sprint backlog) are not affected.
- **DRY:** The fix is one-shot — there is no duplicated formatting logic to consolidate. The *workflow* duplication across plugin repos is sprint 04's problem.
- **Variable naming (per `feedback_variable_naming.md`):** the existing names (`cart_total`, `domestic_countries`, `is_domestic`, `free_above`) are already full and readable. Do **not** rename — out of scope and would invalidate `git blame` linkage.
- **No `# fmt: off` / `# noqa`** — `feedback_no_noqa_without_permission.md`. The fix is "let Black win".

## 5. Acceptance criteria

- [ ] `./bin/pre-commit-check.sh --plugin shipping_flat_rate --quick` exits `0` locally.
- [ ] `docker compose run --rm test pytest plugins/shipping_flat_rate/tests/unit/ -v` exits `0` and reports the same number of passing tests as before the change.
- [ ] `git diff` shows exactly one hunk in `shipping_flat_rate/provider.py` matching the Black diff above. No other files modified.
- [ ] Push to `VBWD-platform/vbwd-plugin-shipping_flat_rate` `main`. CI run `CI — shipping_flat_rate` flips to `completed/success`.
- [ ] `./recipes/ci-status.sh` shows `vbwd-plugin-shipping_flat_rate completed/success` on the next run.

## 6. Commit / push procedure

```bash
cd vbwd-backend/plugins/shipping_flat_rate
git status                   # confirm only provider.py modified
git diff shipping_flat_rate/provider.py
git add shipping_flat_rate/provider.py
git commit -m "style: reformat provider.py per Black (single-line sum)"
git push origin main
```

Then watch the CI run:

```bash
gh run watch --repo VBWD-platform/vbwd-plugin-shipping_flat_rate
```

Per `feedback_no_tagging_unreleased.md` we do **not** tag this push — it is a CI repair, not a release.

## 7. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Black version drift between local and CI | Low | CI installs Black via `vbwd-backend/requirements.txt`; local runs through the same `test` compose service which uses the same image. Both → `black-23.12.1` per the run log install summary. |
| Hidden formatting drift in other plugin files | Low | Step 1 captures Black's full output. If more files appear, scope expands → split into a sprint 01b before pushing. |
| Behavior regression from reflow | Negligible | Black guarantees AST-equivalence; behavior preservation test in §3.2 is the safety net. |
