# Sprint 43 — DB table-naming normalization (plugin-prefix every table)

**Status:** PLANNED — 2026-05-30
**Source:** [report 02 — DB table-naming audit](../reports/02-db-table-naming-audit.md) (verified vs models + live DB).
**Area:** `vbwd-backend` core + plugins `meinchat`, `taro`, `discount`, `booking`, `subscription`, `toss_payments`; cross-plugin `ghrm`. Each ships via its own standalone repo.

## Engineering requirements (BINDING)

TDD-first · DevOps-first · SOLID · DI · DRY · **Liskov** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin <name> --full` green on every touched repo = "done"; `--quick` while iterating. Canonical: `docs/dev_log/20260525/sprints/_engineering-requirements.md`. Plugins live in their own repos ([[feedback_plugins_always_in_own_repos]]); deploy is GitHub-only ([[feedback_deploy_github_only]]).

## Goal

Enforce one table-naming convention so every table announces its owner and can't collide across modules:

| Layer | Rule |
|---|---|
| Core (`vbwd/`) | `vbwd_<table>` — already 100 % compliant, untouched |
| Plugin / module | `<plugin_id>_<model_name>` |

## Decisions locked (2026-05-30)

1. **`discount` keeps `plugin_id="discount"`** (singular) → prefix `discount_` (NOT `discounts_`). No plugin/repo rename.
2. **`subscription` IS renamed this sprint** `vbwd_*` → `subscription_*` (it was extracted from core but is a plugin; the cross-plugin `ghrm` FK is updated in lockstep).
3. **toss_payments:** rename ONLY `toss_cash_receipts` → `toss_payments_cash_receipts`. **Keep the main `toss_payments` table** (== plugin_id, acceptable as the primary table) — confirmed 2026-05-31.
4. Migrations are **idempotent + `_table_exists`/`_index_exists` guarded** (booking/discount have no `migrations/` dir; the legacy monolith `vbwd_001` still emits old names in prod) — [[project_migration_graph_fragmentation]] lesson.

### Rollout decisions (locked 2026-05-31)
5. **Downtime: brief window is acceptable.** `deploy.sh` does `up -d` (new code) → wait health → `--migrate`, so each rename causes ~10–30 s of 500s on the affected routes per instance while `alembic upgrade heads` runs. Fine for the demo instances → **no transitional views / no zero-downtime shim** (no-overengineering).
6. **Scope: ALL instances** — main (vbwd.cc) + shop + hotel + doctor + ghrm. `subscription` runs everywhere; `discount`→shop, `booking`→hotel/doctor, `taro`+`meinchat`→main, `ghrm` FK→ghrm. Roll out per the risk sequencing below; the guarded migrations are idempotent across every instance DB.
7. **Clean cut — all references are internal.** Nothing outside the plugin model code references these table names (no external BI/analytics, no raw-SQL tooling). Part of each rename's DoD: `grep` the plugin repo for the old name in `ForeignKey("…")`, `relationship(…)`, raw `op.execute`, seeders/`populate_db.py` — fix all; **no compatibility views needed.**

## Scope — renames (16 tables across 6 plugins)

### S43.0 — meinchat (5 tables) · repo `vbwd-plugin-meinchat` · 9 existing migrations
| Current | New |
|---|---|
| `conversation` | `meinchat_conversation` |
| `message` | `meinchat_message` |
| `token_transfer` | `meinchat_token_transfer` |
| `user_contact` | `meinchat_user_contact` |
| `user_nickname` | `meinchat_user_nickname` |
- Update the `meinchat_attachment` → `message` FK; `conversation`/`message` internal FKs (2 + 4 refs). `token_transfer`/`user_contact`/`user_nickname` have **0 FKs** → do these three FIRST (lowest risk in the whole sprint).
- **⚠ CROSS-PLUGIN LOCKSTEP (found 2026-05-31, audit missed it): renaming `message` couples `meinchat_plus`.** `meinchat_plus.meinchat_plus_message_delivery.message_id` → `message.id` (`models/message_delivery.py:34`). Postgres auto-follows the table rename for the DB FK constraint, but the **meinchat_plus model FK string must change to `meinchat_message.id`** and ship together (+ meinchat_plus CI/tests must have the renamed meinchat table). The historical meinchat_plus migration `20260601_...` keeps `message.id` (correct — `message` still exists when it runs). So the `message` rename = meinchat **+** meinchat_plus, like subscription↔ghrm.
- fe-user `meinchat` + fe-admin `meinchat-admin` read via the API (no table names) → no FE change expected; verify.

### S43.1 — taro (1) · repo `vbwd-plugin-taro` · 2 existing migrations
| `arcana` | `taro_arcana` | (`taro_card_draw` FK → update) |

### S43.2 — discount (3) · repo `vbwd-plugin-discount` · **NO migrations dir → create one + register in `alembic.ini`**
| `coupon` | `discount_coupon` |
| `coupon_usage` | `discount_coupon_usage` |
| `discount` | **`discount_rule`** (confirmed 2026-05-30) — class `Discount` → **`DiscountRule`** |
- `discount_application` already compliant; update its FK to the renamed parent.

### S43.3 — booking (1) · repo `vbwd-plugin-booking` · **NO migrations dir → create one + register**
| `booking` | `booking_reservation` |
- **7 internal FKs** (`booking_resource_slot_block`, custom_schema, export_rule, …) → rename in lockstep.

### S43.4 — subscription (5) · repo `vbwd-plugin-subscription` · **cross-plugin (ghrm)** — HIGHEST RISK, do LAST
| Current | New | Class |
|---|---|---|
| `vbwd_subscription` | **`subscription_record`** (confirmed) | `Subscription` → **`SubscriptionRecord`** |
| `vbwd_addon` | `subscription_addon` | `AddOn` (ok) |
| `vbwd_addon_subscription` | `subscription_addon_subscription` | `AddOnSubscription` (ok) |
| `vbwd_tarif_plan` | `subscription_tarif_plan` | `TarifPlan` (ok) |
| `vbwd_tarif_plan_category` | `subscription_tarif_plan_category` | `TarifPlanCategory` (ok) |
- **Cross-plugin FK (lockstep): `ghrm.ghrm_software_package.tarif_plan_id` → `vbwd_tarif_plan.id`** becomes `subscription_tarif_plan.id` (repo `vbwd-plugin-ghrm`). Migration + model + CI must land together.
- Core invoice link is **FK-free** (Sprint 11: invoice ↔ subscription via `item_id` UUID, no FK) → core needs no change. Payment plugins use the `ISubscriptionLifecycle` port (no FK). Verify both.
- `vbwd_tarif_plan` has 7 FK refs total (subscription-internal + ghrm).

### S43.5 — toss_payments (1, minor) · repo `vbwd-plugin-toss-payments`
| `toss_cash_receipts` | `toss_payments_cash_receipts` |
| `toss_payments` | *(unchanged — kept as the primary table, decision #3)* |

**No change:** core (`vbwd_*`), cms, shop, ghrm-own, email, meinchat_plus, c2p2/conekta/mercado_pago/promptpay/truemoney (plugin-id-prefixed; plural style only).

## Python model class names (checked 2026-05-30)

Class names are module-scoped (`plugins.<p>.<p>.models.<x>.<Class>`), so generic names don't collide and a **mass class rename is overengineering**. Rename a class ONLY where the table's *meaning* changes:
- `Discount` → **`DiscountRule`** (table `discount` → `discount_rule`).
- `Subscription` → **`SubscriptionRecord`** (table `vbwd_subscription` → `subscription_record`).
- Keep as-is (concept-preserving prefix only): `Conversation`, `Message`, `TokenTransferRecord`, `UserContact`, `UserNickname`, `Arcana`, `Booking`, `Coupon`, `CouponUsage`, `AddOn`, `TarifPlan`, `TarifPlanCategory`, `AddOnSubscription`.
  - When renaming the class, update every import site + `relationship()` target string + the DI/repository wiring.

## Per-rename mechanical checklist (DoD for each table)

1. `__tablename__` updated in the model.
2. Alembic migration: `op.rename_table(old, new)` **guarded** (`if _table_exists(old) and not _table_exists(new)`), **down_revision** correct, **revision id ≤ 32 chars** (report 21 gotcha).
3. **Rename Postgres dependents** Postgres does NOT auto-rename: `<old>_pkey` → `<new>_pkey`, every `ix_<old>_*`, unique constraints, sequences (`<old>_id_seq`), `CHECK` constraint names. Add explicit `op.execute("ALTER ... RENAME ...")` for each.
4. Update every `ForeignKey("<old>.id")` string + SQLAlchemy `relationship`/`backref` + any raw SQL.
5. booking/discount: create `plugins/<p>/migrations/versions/`, register path in `alembic.ini` `version_locations`.
6. `bin/pre-commit-check.sh --plugin <p> --full` GREEN; migration validated **up → down → up** on a live DB.
7. Ship via the plugin's standalone repo; CI green; (deploy via GitHub workflow when SSH unblocked).

## Sequencing (low → high risk)
1. **S43.0a** meinchat `token_transfer`/`user_contact`/`user_nickname` (0 FK).
2. **S43.1** taro `arcana` (1 FK).
3. **S43.0b** meinchat `conversation`/`message` (2 + 4 FK).
4. **S43.2** discount (new migrations dir).
5. **S43.3** booking (7 internal FK + new migrations dir).
6. **S43.4** subscription + ghrm lockstep (cross-plugin) — last, most careful.
7. **S43.5** toss (cosmetic).

## Risks
- **Monolith vs per-plugin:** prod `vbwd_001` still creates old names; the guarded rename migration must run against both a monolith-built prod DB and a `create_all` dev DB → idempotency mandatory.
- **Index/constraint drift:** forgetting to rename `ix_*`/`*_pkey` leaves confusing names and can break later autogenerate diffs.
- **Cross-plugin clone sets:** subscription+ghrm CI must clone each other (declared deps) so `alembic upgrade heads` resolves ([[project_migration_graph_fragmentation]]).
- **Per-instance migrate window:** decision #5 — each rename briefly 500s the affected routes on every instance during `--migrate`; acceptable, no shim.

## Definition of done
All 16 tables renamed (names locked: `discount_rule`, `subscription_record`); every touched plugin's `--plugin … --full` green; each migration up/down/up-validated; cross-plugin ghrm↔subscription lands together; old name absent from every plugin repo (`ForeignKey`/`relationship`/raw SQL/seeders grepped clean); **all 5 instances** show zero bare/orphan table names (`pg_tables` filter from the audit returns empty); changes pushed to each standalone repo.
