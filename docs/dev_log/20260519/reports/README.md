# Reports — 2026-05-19

| # | Report | Type |
|---|---|---|
| [01](./01-subscription-extraction-leftovers-and-effort.md) | Subscription extraction — leftover audit + effort estimates (both directions). **Partially superseded** by 02. | Investigation / architecture |
| [02](./02-phase0-outcome-and-locked-decisions.md) | **Authoritative.** Phase 0 outcome, the audit correction (FE "duplicates" are live plugin→core imports), and the 4 locked decisions. | Decision record |

**Headline:** The 2026-03-27 subscription extraction is functionally live
(plugins authoritative) but physically half-done. Direction **A** chosen.
Phase 0 (dead-code removal) is **done & verified**, and in doing so falsified
part of report 01's frontend audit: the supposed FE "dead duplicates" are
**live shared core code imported by plugins via `@/`**. Report 02 is the
authoritative re-baseline; Sprints 03–08 were revised to match. Locked
decisions: D1 FE re-baseline · D2 subscription DB schema → plugin migration ·
D3 entitlement config-flag/allow · D4 invoices+tokens stay core.
