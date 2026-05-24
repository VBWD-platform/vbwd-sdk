# Sprints — 2026-05-19 — Subscription Extraction, Direction A (finish the move)

> **Live status:** [`../status.md`](../status.md) (this index's status column
> is the original plan; finished sprints have moved to [`../done/`](../done/)).

**Decision:** Direction A from
[`../reports/01-subscription-extraction-leftovers-and-effort.md`](../reports/01-subscription-extraction-leftovers-and-effort.md)
— complete the 2026-03-27 extraction so *subscription* is a true plugin peer
of *shop / booking / ghrm*, and core is provably subscription-agnostic.

**Engineering requirements:**
[`_engineering-requirements.md`](./_engineering-requirements.md) (inherits
[`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md)).
Binding for every sprint below. E1–E6 are extraction-specific.

**Prime directive:** every sprint is a **behaviour-preserving relocation**
(E2). The acceptance oracle is **agnosticism** (E3), automated in Sprint 09.

---

## Why this is phased

The leftover is not a mop-up; it is a deferred "Phase 2" the dev log wrongly
recorded as Done. Phasing makes value land incrementally and keeps each PR
reviewable and revertible:

- **Phase 0 — Safe deletion (no behaviour change, pure subtraction).**
  Remove the ~16 dead duplicate files + 7 orphaned backend routes that
  *no live code reaches*. Shrinks the surface and kills the "edit the
  wrong copy" hazard before any architectural change. Independently
  shippable; safe to do even if the programme later pauses.
- **Phase 1 — Core decoupling (the architectural payoff).** Plugin owns
  its models + migration; live core↔subscription couplings replaced by
  extension points; fe-core purged. This is what actually delivers
  "a booking-only install carries no subscription".
- **Phase 2 — Proof.** The agnosticism oracle automated as a CI exit gate.

---

## Status (2026-05-19)

**Phase 0 DONE & verified** (Sprints 01–02). Phase 1 **re-baselined** —
read [`../reports/02-phase0-outcome-and-locked-decisions.md`](../reports/02-phase0-outcome-and-locked-decisions.md)
before starting any Phase 1 sprint. Four decisions locked there (D1 FE
re-baseline · D2 subscription DB schema → plugin migration · D3 entitlement
config-flag/allow · D4 invoices+tokens stay core). Sprints 03/04/06/07/08
below have been revised to agree with it.

## Sprint index

| # | Sprint | Phase | Status | Effort |
|---|---|---|---|---|
| [01](../done/01-backend-delete-dead-subscription-code.md) | Backend: delete dead/orphaned subscription code | 0 | ✅ done (750/4 == baseline) | M (2) |
| [02](../done/02-frontend-delete-dead-duplicate-views.md) | Frontend: delete dead duplicate views/stores | 0 | ✅ done (FE deadness corrected) | M (2) |
| [03+04](../done/03-merged-decouple-core-and-relocate-subscription.md) | **MERGED** — decouple core (S1–S5) → relocate models no-shim (S6) → plugin migration D2 (S7/03b) | 1 | Baseline ✅; S1– in progress | XL (7–9) ⚠ |
| ~~03~~ / ~~04~~ | superseded → merged doc above (kept for history) | — | superseded | — |
| [05](../done/05-backend-email-templates-to-plugin.md) | Backend: subscription email templates → plugin | 1 | unchanged | S–M (1–2) |
| [06](../done/06-fe-core-purge-subscription.md) | fe-core: purge subscription (org-wide E1 gate) | 1 | revised | M (2) |
| [07](../done/07-fe-user-de-hardcode-nav-router-i18n.md) | fe-user: nav/i18n/Dashboard only — invoices+tokens stay core (D4) | 1 | revised, **shrunk** | S–M (1.5–2) |
| [08](./08-fe-admin-resolve-live-couplings.md) | fe-admin: P1 user/access decoupling + P2 plugin→core `@/` inversion | 1 | revised | L (3–4) ⚠ |
| [09](./09-cross-repo-agnostic-install-proof.md) | Cross-repo agnostic-install proof + CI exit gate | 2 | unchanged | M (2) |

**Rollup:** ~18–24 dev-days (report §5 said 15–22; Sprint 09 + E1
characterisation overhead pushes the realistic upper bound). Excludes
product/QA sign-off and any prod data-migration window (Sprint 03 risk).

---

## Dependency graph (execution order)

```
01 ─┐                      (Phase 0 — parallelisable, no deps)
02 ─┘
        ↓ (Phase 0 merged → smaller, safer surface)
03 ───────────────► 04 ───► 05            (backend chain; 03 gates 04)
06  (fe-core; independent, but its dist/submodule bump gates 07 & 08)
        ↓
07  (fe-user)      08  (fe-admin)          (parallel after 06)
        ↓
        09  (proof; requires 01–08 merged)  ← programme exit gate
```

- **01, 02** have no dependencies — start immediately, in parallel.
- **03 → 04**: live couplings (04) can only be cleanly cut once the plugin
  owns the models (03); doing 04 first would re-import core models.
- **06 before 07/08**: fe-core changes require a `dist/` build + submodule
  pin bump (per `MEMORY.md` no-host-npm rule + lockfile-pin lesson) that
  fe-user/fe-admin consume.
- **09 last**: it asserts the whole oracle; it is the merge gate, not a
  parallel task.

## Cross-cutting rules (all sprints)

- **E2 above all:** no behaviour change in a move. Improvements are
  separate, later, RED-tested sprints.
- Each sprint opens with a **Baseline** section: the exact characterisation
  test(s) and the green command output proving current behaviour, per E1.
- Each sprint closes with the **slice of the E3 oracle it makes pass**.
- Plugin code lands in the standalone plugin repos, committed to `main`,
  no temp branches (E5).
- `bin/pre-commit-check.sh --full` green on every touched repo before merge
  (inherited §2).
- Dev log honesty: a sprint is "Done" only when its oracle slice is
  demonstrably green. Do **not** repeat the 04c mistake of recording a
  cleanup as Done while it is absent from `main`.
