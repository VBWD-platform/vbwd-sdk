# Engineering requirements — BINDING for every sub-sprint in this directory

Inherits the canonical statement at
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md)
and the extraction rules at
[`../../20260519/sprints/_engineering-requirements.md`](../../20260519/sprints/_engineering-requirements.md).
Re-stated here so every sprint file can link a single anchor.

## The core requirements (no exceptions)

1. **TDD-first.** The change starts with a failing test (characterisation
   test capturing today's behaviour, or oracle test asserting the new contract).
   Red → green → refactor. No code lands without a test.
2. **DevOps-first.** Works local AND in CI from a cold start. Schema only
   via Alembic — never raw SQL. Validate at every step (lint + unit +
   integration + app boot). No "works on my machine".
3. **SOLID.**
   - *S* Single responsibility — one reason to change per module.
   - *O* Open/closed — extend via ports/registries; never modify core for
     a plugin's feature.
   - *L* Liskov — every subtype (concrete impl, null default, test fake)
     honours the base contract; a port swap is behaviour-preserving; the
     disabled-plugin path must not break callers.
   - *I* Interface segregation — narrow ports; consumers depend only on
     the methods they use.
   - *D* Dependency inversion — depend on the abstraction (port / container
     provider / registry), never on a concrete plugin module or model.
4. **DI.** Resolve collaborators through the container / `resolve_*` ports
   / registries. No `import` of a plugin's models or repos from core, and
   no other-plugin runtime import without a declared
   `PluginMetadata.dependencies` entry.
5. **DRY.** One home for each behaviour — payment-route helpers live in
   `vbwd/plugins/payment_route_helpers.py`; renewal-invoice creation lives
   in the lifecycle impl only; timestamps + `to_dict()` live in a single
   `BaseModel` / shared mixin.
6. **Liskov (called out again because we just shipped a violation).**
   Subtypes never silently return `success=False` for a structurally
   unsupported operation — raise `UnsupportedOperationError` and let the
   caller decide. Fakes used in tests obey the same contract.
7. **Clean code.** Full readable names ([[feedback_variable_naming]]);
   small focused functions (<50 LOC, classes <300 LOC); no bare
   `except Exception: pass`; no magic numbers — extract constants;
   no commented-out code; no dead methods.
8. **NO OVERENGINEERING.** The narrowest change that satisfies the
   requirement. No new layers "just in case"; a port gets exactly the
   methods today's callers need. Single-implementation ports stay only
   if they cross the core⇄plugin boundary (extension surface earned its
   keep). Otherwise inline.

## Quality gate (the guard)

`bin/pre-commit-check.sh --full` (black + flake8 + mypy + unit +
integration) must be green on every touched repo before the sprint is
marked done.

- Quick loop while iterating: `bin/pre-commit-check.sh --quick`
  (lint + unit).
- Lint only: `bin/pre-commit-check.sh --lint`.
- No silenced findings: no unreviewed `# noqa`, no `# type: ignore`.
  Fix the root cause or ask first
  ([[feedback_no_noqa_without_permission]]).

## Done = all of:

TDD'd · DevOps-clean (local + CI green) · SOLID/DI/DRY/Liskov/clean ·
not over-engineered · the slice's oracle assertion green ·
`pre-commit-check.sh --full` green on every touched repo · no commits
unless explicitly instructed ([[feedback_no_commit_without_ask]]).

## Source audit

These sprints come from
[`../reports/01-backend-pattern-and-agnosticism-review.md`](../reports/01-backend-pattern-and-agnosticism-review.md).
Each sprint cites the section that triggered it.
