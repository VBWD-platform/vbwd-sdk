# Sprint 49.5 — fe-user GitHub tab (per-package states + PAT/clone)

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decisions:** D2, D3, D6, D7
**Status:** READY · **Area:** `vbwd-fe-user-plugin-ghrm` (its own repo, [[feedback_plugins_always_in_own_repos]])
**Depends on:** **S49.4** (`/access` + install payload shapes). **Blocks:** nothing.

## Engineering requirements (BINDING)
TDD-first (Vitest) · SOLID · DRY · clean code · NO OVERENGINEERING. ESLint clean ([[feedback_ci_precommit_lessons]] — run full `npm run lint`). Generic styles via `var(--vbwd-*)`. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
The GitHub tab must reflect **real** per-package membership state (no more false "connected") and give an `ACTIVE` user the clone path via their own fine-grained PAT.

## UI behaviour (driven by `GET /api/v1/ghrm/access`)
For each membership in `memberships[]`, render a row with package name + a state chip:
| status | copy / CTA |
|---|---|
| `ACTIVE` | "Connected — clone access granted" + **Install panel** (PAT steps + clone command) |
| `INVITED` | "Invitation sent — **accept it on GitHub**" + link to `invitations_url` / the repo's invitations page |
| `GRACE` | "Access ends on {grace_expires_at}" (renew prompt) |
| `REVOKED` | "Access ended — renew your subscription" |
| `ERROR` | "Connection error — please contact support" (never shows "connected") (D6) |
- `connected === false` → the "Connect GitHub" CTA (OAuth start) as today.
- Install panel (ACTIVE): show the steps to create a fine-grained PAT (`Contents: read` on the repo) and the `git clone` command from `GET …/install`; copy-to-clipboard. **Never render a server token** (none exists, D3).

## TDD plan (tests FIRST — Vitest/jsdom, mocked api)
- each status → correct chip + copy; `ERROR` never renders the ACTIVE/"connected" affordance.
- `ACTIVE` → install panel shows PAT steps + clone command (assert the command string from the mocked install payload).
- `INVITED` → "accept invitation" link points at `invitations_url`.
- `connected:false` → Connect CTA only; multiple memberships → multiple rows (D7).

## Implementation steps
1. Write failing Vitest specs for the five states + connect + install panel.
2. Update the tab component + store to consume `memberships[]` and the install payload; remove any deploy-token UI.
3. `npm run test` + full `npm run lint` green; push the plugin repo (its CI green) per [[feedback_no_temp_branches]].

## Definition of done
The tab renders accurate per-package state, an ERROR never masquerades as connected, ACTIVE users get PAT+clone guidance, no server token is shown; Vitest + ESLint green; plugin repo pushed with green CI.
