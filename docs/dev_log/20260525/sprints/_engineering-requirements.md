# Engineering requirements — BINDING for every sub-sprint

These are the project's core requirements. **Every** sub-sprint file references
this. A slice is not "done" until all of these hold and the quality gate is green.
Inherits the extraction rules E1–E6 in
[`../../20260519/sprints/_engineering-requirements.md`](../../20260519/sprints/_engineering-requirements.md).

## The core requirements

1. **TDD-first.** Write/extend the test before (or with) the change. Each slice
   opens with a characterisation test capturing current behaviour (E1) and
   closes with the assertion that proves the new contract. Red → green → refactor.
2. **DevOps-first.** The change must run cleanly local **and** in CI from a cold
   start. No "works on my machine"; no manual DB edits — schema only via Alembic.
   Validate after every step (agnostic oracle + integration + app boot).
3. **SOLID.**
   - *S* — one reason to change per module (ports/handlers are single-purpose).
   - *O* — extend via registries/ports, don't modify core for a plugin.
   - *L* — **Liskov:** a port/handler swap (incl. the null default) is behaviour-
     preserving; the disabled-plugin path must not break callers.
   - *I* — narrow ports (only the methods a consumer needs).
   - *D* — **DI:** depend on the abstraction (port / `container` provider /
     registry), never on a concrete plugin or model.
4. **DI.** Resolve collaborators through the container / `resolve_*` ports /
   registries. No `import` of a plugin's models or repos from core or another
   plugin's runtime.
5. **DRY.** One home for each behaviour (e.g. renewal-invoice creation lives in
   the lifecycle impl only; recurring logic in the line-item registry only).
6. **Liskov.** Subtypes (concrete port impls, null defaults, fake test doubles)
   honour the base contract exactly — substitutable without surprising callers.
7. **Clean code.** Full readable names; small focused functions; behaviour-
   preserving moves (E2); no dead code left behind.
8. **NO OVERENGINEERING.** The narrowest change that satisfies the requirement.
   No speculative abstractions, no new layers "just in case." A port gets exactly
   the methods today's callers need — nothing more.

## Quality gate (the guard)

`bin/pre-commit-check.sh --full` (black + flake8 + mypy + unit + integration)
must be **green on every touched repo** before a sub-sprint is marked done.
- Quick loop while working: `bin/pre-commit-check.sh --quick` (lint + unit).
- Lint only: `bin/pre-commit-check.sh --lint`.
- It is the single source of truth for "is this mergeable" — do not hand-wave
  past it (no unreviewed `# noqa` / `# type: ignore`; fix the root cause).

## Done = all of:
TDD'd · DevOps-clean (local + CI) · SOLID/DI/DRY/Liskov/clean · not
overengineered · the slice's oracle assertion green · `pre-commit-check.sh
--full` green · no commits unless explicitly instructed.
