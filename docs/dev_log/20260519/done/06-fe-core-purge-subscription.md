# Sprint 06 — fe-core: purge subscription from the shared library

**Phase:** 1 · **Repos:** `vbwd-fe-core` (+ consumers' submodule pins)
**Effort:** M (~2 dev-days, coordination-heavy) · **Depends on:** 02
**Blocks:** 07, 08 · **Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding (esp. **E5**, `MEMORY.md` no-host-npm + lockfile-pin).

## Re-baseline note (read first)

[`../reports/02-phase0-outcome-and-locked-decisions.md`](../reports/02-phase0-outcome-and-locked-decisions.md)
§2: Phase 0 proved the original audit **over-stated frontend deadness** —
files called "dead" were live plugin→core imports. Phase 0 did **not** touch
`vbwd-fe-core`, so this sprint's findings are unverified by implementation.
Therefore the **E1 RED-gate is mandatory and org-wide here**: before
deleting any exported symbol, prove zero importers across **every** consuming
repo (fe-user, fe-admin, all their plugins, pitchmacher, any other
`vbwd-view-component` consumer) — not just the two known frontends. A shared
library's public API has the widest blast radius; assume the audit is wrong
until the grep + typecheck prove a symbol dead. Anything still imported is
**generalised, not deleted** (track-generalise below).

## Goal

`vbwd-fe-core` is the shared `vbwd-view-component` library. It must be
feature-agnostic. It currently exports a subscription store, a
subscription-coupled composable, and `SUBSCRIPTION_*` events — and the audit
found **no consumer** of them (dead *and* a worst-tier agnosticism violation,
report §3.3, §4.1).

Two-track per item: **(track-dead)** confirmed-unused subscription API →
delete; **(track-generalise)** generic primitive with subscription vocabulary
baked in → rename/parameterise so it carries no domain word.

## In scope

| File | Track | Action |
|---|---|---|
| `src/stores/subscription.ts` + `src/stores/index.ts:12-13` exports | dead | delete store + public exports (`useSubscriptionStore`, `SubscriptionState`, `FeatureUsage`) |
| `src/composables/useFeatureAccess.ts` | dead | delete (imports the dead store; no consumer) |
| `src/events/events.ts:22-28,99-102,181-186` (`SUBSCRIPTION_*`, `SubscriptionPayload`) | dead | delete the subscription events + payload type from the shared bus |
| `src/components/access/FeatureGate.vue`, `UsageLimit.vue` | generalise | keep the generic gate; remove subscription wording — props become `requiredCapability` / generic copy; **no** "plan" string in the lib |
| `src/stores/cart.ts:8` `CartItemType`, `components/cart/CartItem.vue` label | generalise | `CartItemType` becomes an open `string` (or generic union) so subscription kinds aren't enumerated in core; label resolved by caller |
| `src/composables/usePaymentRedirect.ts` | keep | already generic (invoice id) — no change |

## Baseline (E1)

- Cross-repo grep proving zero consumers of the **dead** track in
  `vbwd-fe-user/**` and `vbwd-fe-admin/**` (the audit's key finding — fe-user
  views import the *fe-user-local* store, not this one). Record the empty
  grep.
- For the **generalise** track: Vitest char specs pinning current rendered
  output of `FeatureGate`/`UsageLimit`/`CartItem` with representative props.
  GREEN before change; GREEN after (E2 — visual/behaviour unchanged, only the
  vocabulary/prop names change → update the spec's *inputs* to the new prop
  names but assert the *same rendered output*).

## TDD plan

1. **RED (deadness):** add `tests/no-domain-words.spec.ts` asserting the
   built public surface (`src/index.ts` exports + `events.ts`) contains no
   `subscription`/`Subscription` identifier. Red now; green after deletes.
2. Delete the dead track. Library typecheck (`vue-tsc`) + `npm run build`
   (in container — **never host npm**, `MEMORY.md`) must pass; a break ⇒ a
   hidden consumer ⇒ escalate (it's not actually dead).
3. **Generalise track, behaviour-frozen:** rename props/types; update the
   Baseline char specs' inputs only; assert identical rendered DOM/output
   (E2). `FeatureGate` requiredCapability is a generic string; the *meaning*
   ("show slot when capability present") is unchanged.
4. **Consumer compatibility:** since 02 already deleted fe-user/fe-admin code
   that might reference these, re-run a cross-repo grep → zero references.
   Any remaining reference is updated to the generic name **in that consumer
   repo's own sprint (07/08)**, not here.

## Release / submodule discipline (E5 + MEMORY)

- fe-core change requires a **`dist/` rebuild** and a **submodule pin bump**
  in fe-user/fe-admin (per `MEMORY.md` no-host-npm-in-bind-mounts +
  `project_pitchmacher_lockfile_pin` style: prod consumes pinned, not
  `#main`). This sprint produces the built `dist/` + records the new pin SHA;
  Sprints 07/08 consume that pin. The bump is the explicit interface between
  this sprint and the frontend sprints (README dependency graph).
- Build runs in the fe-core dev container, not on the host.

## SOLID / clean-code notes

- **SRP/ISP:** a shared UI library exposes generic capability primitives, not
  a subscription domain model. Narrow the public surface.
- **OCP:** features extend via app/plugin code, never by the library knowing
  feature names.
- **DRY:** removes a dead second feature-access implementation (the live one
  is the plugin's).
- Clean code: generic names (`requiredCapability`), zero domain words in the
  library; no "what" comments.

## Acceptance criteria

- Dead track deleted; `no-domain-words.spec.ts` green; `vue-tsc` +
  `npm run build` clean in-container.
- Generalise-track char specs green with identical rendered output under the
  new generic prop/type names.
- New `dist/` built; new submodule pin SHA recorded in this sprint's PR for
  07/08 to consume.
- Project-wide `npm run lint` clean.

### E3 oracle slice made true

"the shared `vbwd-view-component` public API contains zero subscription
identifiers" (the highest-severity violation, fully closed).

## Risks

- A consumer outside the two known frontends (e.g. fe-admin plugins,
  pitchmacher) imports a deleted symbol. Mitigation: org-wide grep before
  delete; the deadness spec; consumers are pinned (won't break until they bump
  the pin in 07/08, where the rename is handled).
- Host-npm pollution of fe-core native binaries (`MEMORY.md`). Mitigation:
  build only in-container; never `npm install` on host here.

## Effort

M — ~2 dev-days; cost is coordination (build + pin), not code volume.
