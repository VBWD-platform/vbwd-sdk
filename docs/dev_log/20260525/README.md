# 2026-05-25 — Continue Sprint 11 (subscription extraction: models leave core)

Carry-over from 2026-05-24. This day finishes
[Sprint 11](../20260519/sprints/11-complete-subscription-extraction.md):
make subscription a fully self-contained plugin so **core keeps only**
`user`, `user_details`, `token*`, `invoice`, `invoice_line_item`.

## Start here, in order
1. [`reports/01-sprint11-day1-outcome-and-lessons.md`](reports/01-sprint11-day1-outcome-and-lessons.md)
   — what's done, what's red, and the **lessons** (esp. S4/S5 = R4 FK coupling).
2. [`sprints/README.md`](sprints/README.md) — the remaining sub-sprints + order.
3. Run the §6 sanity commands in the report (done-work should be green).

## State in one line
**Sprint 11 functionally COMPLETE** — S1–S7 all ✅. Core keeps only
user/userdetails/token*/invoice/line-item; the 5 models live in the plugin; the
invoice has no subscription FK (link = SUBSCRIPTION line item); payment plugins
use the lifecycle port; both FE apps' core invoice views/stores are
subscription-agnostic (`invoiceDetailSections` + generic `/deletion-info
dependencies[]`); all 3 agnosticism oracles flipped + decision log updated.
Backend green (884 core+sub, 199 payment) + lint; fe-admin 441 green; fe-user
478 green; migration validated. Optional **S8** (permission namespace) deferred.
No commits made. See reports
[`02`](reports/02-sprint11-day2-backend-complete.md) +
[`03`](reports/03-sprint11-day2-fe-and-oracles-complete.md).

## Core engineering requirements (binding, every slice)
TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **no
overengineering**, gated by `bin/pre-commit-check.sh --full`. See
[`sprints/_engineering-requirements.md`](sprints/_engineering-requirements.md).

## Order of attack tomorrow
`S4` (invoice FK + migration, HIGH risk) → `S5` (move models) → `S7` (flip
oracles); `S6` (FE) after S4; `S1-tests` independent (do it to get CI green).
Validate after **every** step (agnostic oracle + subscription integration +
app boot) — payment/DB is the high-cost-of-error zone. A slice is "done" only
when `bin/pre-commit-check.sh --full` is green on every touched repo.
