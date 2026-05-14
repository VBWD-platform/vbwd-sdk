# Sprint 04 — Shared CI: harden the pytest "no tests collected" guard

**Status:** PLANNED — 2026-05-14
**Repos touched:** every `vbwd-plugin-*` and `vbwd-fe-*-plugin-*` repo whose `.github/workflows/tests.yml` currently uses the `[ -d "…/integration" ]` guard. Same edit, applied N times via `recipes/setup-plugin-ci.sh` template + a one-shot push loop.
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding.
**Sequenced after:** sprints 02 (shop) and 03 (subscription) — those add *real* coverage so we don't lose visibility when the guard tightens.

---

## 1. Failure analysis (root cause, not symptom)

Sprints 02 and 03 patched two specific plugins, but the underlying defect is in the **shared workflow template** at `recipes/setup-plugin-ci.sh` (and the per-plugin `.github/workflows/tests.yml` files it generates). The guard:

```yaml
if [ -d "plugins/<name>/tests/integration" ]; then
  pytest plugins/<name>/tests/integration/ …
else
  echo "No integration tests — skipping."
fi
```

…is wrong because **the directory existing is not the same as the directory containing tests**. Any `__init__.py`-only scaffold detonates pytest with exit 5.

Per `feedback_ci_precommit_lessons.md` in `MEMORY.md`:

> Skip tests gracefully when plugin has no test files (check dir + find .py)

This was learned-and-recorded but never propagated into the workflow template. Sprint 04 closes that loop.

## 2. Scope

**In:**
- Update the workflow template in `recipes/setup-plugin-ci.sh` (or wherever the canonical template lives — verify first) to use a content-aware guard.
- Apply the same patch to every existing `.github/workflows/tests.yml` across plugin repos.
- Add the same guard to `bin/pre-commit-check.sh` integration block (it has a similar guard — sprint must check before duplicating work; per `feedback_ci_precommit_lessons.md` an existing guard exists at the unit level but the integration block needs the same hardening).

**Out:**
- Workflow restructuring (matrix builds, caching changes, etc.).
- Adding any new test type (e.g. e2e gates).
- Touching frontend (`vbwd-fe-*`) workflows in this sprint — if those have the same defect, file a sprint 04b. We finish backend hardening cleanly first.

## 3. The patch

Replace:

```yaml
if [ -d "plugins/<name>/tests/integration" ]; then
  docker compose --profile test run --rm -T test \
    pytest plugins/<name>/tests/integration/ \
    -v --tb=short \
    --junit-xml=/app/test-results/integration.xml
else
  echo "No integration tests — skipping."
fi
```

With:

```yaml
integration_dir="plugins/<name>/tests/integration"
integration_test_count=0
if [ -d "$integration_dir" ]; then
  integration_test_count=$(find "$integration_dir" -name 'test_*.py' -type f | wc -l)
fi

if [ "$integration_test_count" -gt 0 ]; then
  docker compose --profile test run --rm -T test \
    pytest "$integration_dir" \
    -v --tb=short \
    --junit-xml=/app/test-results/integration.xml
else
  echo "No integration test files found in $integration_dir — skipping."
fi
```

The same shape applies to the unit-test step (where the existing guard is already correct in the template but should be cross-checked).

**Why `find` and not pytest's `--collect-only` then count:** pytest collection needs the full Python environment to import without errors. We must not require importability to make the *guard* decision — that's circular when the import itself is what we're trying to test gradually. `find` is dumb-on-purpose.

## 4. TDD checkpoints

This sprint changes shell + YAML, so "TDD" maps to "write a failing local repro first, then patch, then verify the repro passes":

### TDD cycle 1 — repro the failure with a synthetic empty plugin

```bash
cd vbwd-backend
mkdir -p plugins/__synthetic_empty/tests/integration
touch plugins/__synthetic_empty/tests/integration/__init__.py

# Run the OLD-style guard:
if [ -d "plugins/__synthetic_empty/tests/integration" ]; then
  docker compose --profile test run --rm -T test \
    pytest plugins/__synthetic_empty/tests/integration/ -v
fi
# Expected: exit 5
echo "old-style exit: $?"
```

### TDD cycle 2 — same dir, NEW guard, must skip cleanly

```bash
integration_dir="plugins/__synthetic_empty/tests/integration"
integration_test_count=0
if [ -d "$integration_dir" ]; then
  integration_test_count=$(find "$integration_dir" -name 'test_*.py' -type f | wc -l)
fi
if [ "$integration_test_count" -gt 0 ]; then
  echo "would run pytest"
else
  echo "skipping — no test_*.py"
fi
# Expected stdout: "skipping — no test_*.py"
# Expected exit: 0
```

### TDD cycle 3 — populated dir, NEW guard, must invoke pytest

```bash
cat > plugins/__synthetic_empty/tests/integration/test_smoke.py <<'EOF'
def test_smoke():
    assert True
EOF

# Re-run the new guard:
integration_dir="plugins/__synthetic_empty/tests/integration"
integration_test_count=$(find "$integration_dir" -name 'test_*.py' -type f | wc -l)
[ "$integration_test_count" -gt 0 ] && echo "would run pytest" || echo "skipping"
# Expected: "would run pytest"
```

### TDD cycle 4 — clean up the synthetic plugin

```bash
rm -rf plugins/__synthetic_empty
```

**Why a synthetic plugin and not the real ones:** sprints 02 and 03 *do* land real tests. After they merge, the real shop and subscription `integration/` dirs are no longer empty — so we can't reproduce the failure with them. The synthetic plugin is a test-only construct that proves the guard's behavior in isolation. Per `feedback_no_temp_branches.md`, this synthetic plugin lives only in the developer's working tree, never committed.

### TDD cycle 5 — apply the patch to the template + every workflow

For each plugin repo:

```bash
cd vbwd-backend/plugins/<name>
# manually edit .github/workflows/tests.yml — apply §3 patch
bash -n .github/workflows/tests.yml  # syntax check (per feedback_ci_precommit_lessons.md)
git diff .github/workflows/tests.yml  # review
git add .github/workflows/tests.yml
git commit -m "ci: harden integration guard — skip when no test_*.py files exist

Replaces \`[ -d \$dir ]\` with \`find \$dir -name 'test_*.py' | wc -l\` >0.
Prevents pytest exit 5 ('no tests collected') from breaking CI on
plugins whose integration/ dir holds only __init__.py.

Cross-references feedback_ci_precommit_lessons.md."
git push origin main
```

The `recipes/setup-plugin-ci.sh` template patch is committed in `vbwd-sdk-2`'s root repo (NOT in any plugin repo) — the template generates *future* plugin workflows. Verify with `bash -n recipes/setup-plugin-ci.sh` per `feedback_ci_precommit_lessons.md`.

## 5. SOLID / DRY / clean code applied

- **DRY:** the entire point of this sprint. Today the guard is copy-pasted into ~15 plugin repos with the same bug; we lift the corrected version into the template so the next plugin is born immune.
- **SRP:** the guard does one thing — decide whether pytest should run. It does not also format the output, decide on coverage, or upload artifacts.
- **OCP (workflow):** the guard is structured so adding more file patterns later (e.g. `.feature` files for behave) is one extra `find` clause, not a rewrite.
- **Variable naming:** `integration_dir`, `integration_test_count`. **Not** `d`, `n`, `cnt`. Per `feedback_variable_naming.md`. Same standard in shell as in Python — no exceptions.
- **`bash -n` after every shell edit:** the lesson from `feedback_ci_precommit_lessons.md` ("a stray `fi` breaks ALL jobs"). Sprint cannot push without this gate.
- **No suppression / `# noqa`** — N/A in shell, but the analogous "set -e but ignore exit 5 specifically" workaround is rejected. We fix the guard, we do not suppress the symptom.
- **Migrations only / no raw SQL** — N/A this sprint; mentioned because the engineering doc inlines it.

## 6. Acceptance criteria

- [ ] §4 TDD cycles 1–4 reproduce locally with the documented exit codes.
- [ ] `recipes/setup-plugin-ci.sh` (or the canonical template) reflects the §3 patch; `bash -n recipes/setup-plugin-ci.sh` passes.
- [ ] Every plugin repo whose CI failed in `./recipes/ci-status.sh` due to the empty-`integration/` issue (today: shop, subscription; potentially: any future scaffold-only plugin) has the patched workflow committed and pushed to `main`.
- [ ] `./recipes/ci-status.sh` shows zero `completed/failure` rows attributable to "no tests collected".
- [ ] Sprint report (under `docs/dev_log/20260514/reports/`) lists which plugin repos got the workflow patch and links each push commit.

## 7. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Patching workflow files mid-flight while sprint 02/03 are in progress causes merge conflicts | Low | Sequenced: 02 + 03 land first (only touch test files), then 04 (only touches `.github/workflows/`). Different files → no overlap. |
| `find` count includes hidden `.pyc` or `__pycache__` files | Low | Filter `-name 'test_*.py'` excludes both. |
| Broken `set -e` interaction in CI shell | Low | The new block returns 0 from the conditional explicitly via the `if/else`. `bash -n` catches syntax issues; manual run of TDD cycle 2 catches semantic issues. |
| Workflow change accidentally hides real failures (test file present but pytest can't import it) | Medium | If `find` finds a `test_*.py` but pytest still collects 0, that means the file imports raise — pytest will exit non-zero with the import error and the job correctly fails. The new guard does not mask import errors; it only masks the empty-dir case. |
| `vbwd-fe-*-plugin-*` workflows have the same defect | Medium | Out of scope for this sprint, by design. File sprint 04b after 04 lands and we observe whether `./recipes/ci-status.sh` still shows fe-plugin failures with the same shape. |
