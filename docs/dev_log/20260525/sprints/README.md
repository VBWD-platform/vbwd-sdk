# Sprint 11 (continued) — remaining sub-sprints

Carry-over from 2026-05-24. **Read first:**
[`../reports/01-sprint11-day1-outcome-and-lessons.md`](../reports/01-sprint11-day1-outcome-and-lessons.md).
Original (now split) plan: [`../../20260519/sprints/11-complete-subscription-extraction.md`](../../20260519/sprints/11-complete-subscription-extraction.md).

**Goal:** core keeps only `user`, `user_details`, `token*`, `invoice`,
`invoice_line_item`; subscription becomes a self-contained plugin peer.
Supersedes decision A; resolves R3/R4.

**Core engineering requirements — BINDING for every sub-sprint:** TDD-first ·
DevOps-first · SOLID · DI · DRY · Liskov · clean code · **no overengineering**,
with `bin/pre-commit-check.sh --full` as the quality guard. Full definition:
[`_engineering-requirements.md`](_engineering-requirements.md). Each sub-sprint
file restates this at its top.

## Done already (do NOT redo)
- **S2** — taro/analytics → entitlement + read-model ports ✅
- **S3** — ghrm → catalog read port ✅ (runtime; ghrm seed import handled in S5)
- **S1 code** — payment plugins → `ISubscriptionLifecycle` port + recurring via
  the extensible line-item registry ✅ (proven by tests)
- **S4** — invoice FK removal + core migration ✅ (2026-05-25; migration
  upgrade/downgrade/re-upgrade validated on live data)
- **S5** — 5 model classes moved core→plugin ✅ (2026-05-25; app boots, mapper
  config OK, `User.subscriptions` relationship removed — DB cascade preserved)
- **S1-tests** — stripe/paypal/yookassa webhook tests rewired to the port ✅
  (2026-05-25; 199 green; also fixed paypal/yookassa sdk-adapter import paths +
  `PayPalSDKAdapter.release_authorization`)
- **S7 (backend oracle)** — `test_subscription_agnostic_backend.py` flipped ✅
  (decision-A test deleted; models-left-core asserts added)

See [`../reports/02-sprint11-day2-backend-complete.md`](../reports/02-sprint11-day2-backend-complete.md)
and [`../reports/03-sprint11-day2-fe-and-oracles-complete.md`](../reports/03-sprint11-day2-fe-and-oracles-complete.md).

- **S6** — FE follow-through ✅ (2026-05-25): fe-admin `invoiceDetailSections`
  (Subscription Info moved to subscription-admin plugin), fe-admin + fe-user
  core invoice stores carry no subscription/plan metadata, generic
  `/deletion-info dependencies[]` + fe-admin consumer.
- **S7** — oracles + decision log ✅ (2026-05-25): backend + both FE agnosticism
  oracles flipped; decision log A/R3 superseded, R4 + D4 residuals resolved.

**Sprint 11 functionally complete.** Optional **S8** (rename core token/invoice
permissions out of `subscription.*`) deferred — cosmetic, ship separately.

```
S4 ──► S5 ──► S7
  └──► S6
S1-tests  (independent; can run anytime to get CI green)
```

## Cadence (non-negotiable, see lessons §5/§6/§7)
- **TDD-first:** test before/with the change (characterise → change → assert).
- Validate after **every** step: agnostic oracle + subscription integration +
  app boot. Payment/DB are the high-cost-of-error zone — do not batch.
- **`bin/pre-commit-check.sh --full` green** on every touched repo = the
  definition of "slice done" (DevOps-first). `--quick` while iterating.
- **No overengineering:** narrowest change that satisfies the requirement.
- No commits without explicit instruction (standing rule).
