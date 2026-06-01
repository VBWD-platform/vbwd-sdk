# Report 02 — DB table-naming audit + rename plan

**Date:** 2026-05-30
**Scope:** every `__tablename__` across `vbwd-backend` core (`vbwd/`) + all plugins, cross-checked against the live `vbwd` DB (`pg_tables`).

## Convention being enforced

| Layer | Prefix rule | Example |
|---|---|---|
| **Core** | `vbwd_<table>` | `vbwd_user`, `vbwd_invoice_line_item` |
| **Plugin / module** | `<plugin_id>_<model_name>` | `taro_arcana`, `booking_reservation`, `discount_coupon` |

Goal: eliminate bare, unprefixed "orphan" table names (`coupon`, `arcana`, `booking`, …) that collide-risk across plugins and hide which module owns them.

## Headline result

- **Core (`vbwd/`): 22 tables, 100 % compliant** — all `vbwd_*`. Nothing to do.
- **11 orphan tables** (bare names, no plugin prefix) across **4 plugins** — confirmed in models AND the live DB. These are the rename targets.
- **1 special case:** the `subscription` plugin uses the **core `vbwd_` prefix** (it was extracted from core) — high-risk to rename, recommend a separate decision.
- **Payment plugins compliant**; `toss_payments` has one minor inconsistency.

## 1. Orphan tables to rename (confirmed in live DB)

| Plugin (`plugin_id`) | Current (orphan) | Proposed | FK refs | Notes |
|---|---|---|---|---|
| **booking** | `booking` | `booking_reservation` | **7** | The main reservation table; 7 internal FKs (`booking_resource_slot_block`, etc.) point at it. Highest internal-FK churn. |
| **taro** | `arcana` | `taro_arcana` | 1 | `taro_card_draw` references it. Other taro tables already compliant (`taro_card_draw`, `taro_session`). |
| **meinchat** | `conversation` | `meinchat_conversation` | 2 | |
| **meinchat** | `message` | `meinchat_message` | 4 | incl. `meinchat_attachment` FK. |
| **meinchat** | `token_transfer` | `meinchat_token_transfer` | 0 | Generic name — easy (no FKs). NB distinct from core `vbwd_token_transaction`. |
| **meinchat** | `user_contact` | `meinchat_user_contact` | 0 | Generic — collision risk with core `vbwd_user*`. |
| **meinchat** | `user_nickname` | `meinchat_user_nickname` | 0 | Generic — collision risk. |
| **discount** | `coupon` | `discount_coupon` | 2 | see plugin-id note below. |
| **discount** | `coupon_usage` | `discount_coupon_usage` | — | |
| **discount** | `discount` | `discount_discount` *(or `discount_rule`)* | 2 | bare = same as plugin_id; needs a model suffix. |

`discount_application` already carries the `discount_` prefix → **compliant**, leave as-is.
`meinchat_attachment` already compliant.

### ⚠ Decision needed — `discount` vs `discounts`
The request examples used **`discounts_coupons` / `discounts_discount`** (plural prefix + plural table), but the plugin's canonical id is **`discount`** (singular; `PluginMetadata(name="discount")`, dir `plugins/discount/`). The prefix must match the `plugin_id`. Two options:
1. **Keep `plugin_id="discount"`** → tables `discount_coupon`, `discount_coupon_usage`, `discount_discount`. *(recommended — no plugin/repo rename)*
2. **Rename the plugin to `discounts`** → tables `discounts_coupon(s)`, `discounts_discount`. Bigger blast radius (dir, repo `vbwd-plugin-discount`, `plugins.json`, fe siblings, CI). 

Pick one before implementing — the table names follow from it.

## 2. Special case — `subscription` uses the core `vbwd_` prefix

`subscription` tables: `vbwd_subscription`, `vbwd_addon`, `vbwd_addon_subscription`, `vbwd_tarif_plan`, `vbwd_tarif_plan_category`. These are a **plugin** but carry the **core** prefix because they were *extracted from core* (Sprint 11 / Direction A). Strict reading of the rule → they should be `subscription_*`.

**Recommend: defer / separate sprint.** Renaming them is the highest-risk item:
- **Cross-plugin FK:** `ghrm.ghrm_software_package → vbwd_tarif_plan` (`ondelete=CASCADE`) — renaming breaks ghrm unless updated in lockstep.
- `vbwd_tarif_plan` has **7 FK refs** total (subscription internal + ghrm + invoice linkage).
- Touches the core↔subscription extraction boundary already documented as fragile ([[project_migration_graph_fragmentation]]).

If kept as `vbwd_*`, document the exception (extracted-from-core legacy). If renamed, it needs its own coordinated migration touching subscription + ghrm + invoice.

## 3. Minor inconsistencies (prefixed but not by full plugin_id)

| Plugin | Table | Strict form | Severity |
|---|---|---|---|
| `toss_payments` | `toss_cash_receipts` | `toss_payments_cash_receipts` | low (uses `toss_` not `toss_payments_`) |
| `toss_payments` | `toss_payments` | `toss_payments_payment` | cosmetic (bare == plugin_id) |
| payments (`c2p2`,`conekta`,`mercado_pago`,`promptpay`,`truemoney`) | `*_transactions`/`*_orders`/`*_payments` | — | **compliant** (plugin-id prefixed; plural style only) — leave |

## 4. Fully-compliant plugins (no action)
`cms` (11 tables), `shop` (12), `ghrm` (4), `email` (1), `c2p2`, `conekta`, `mercado_pago`, `promptpay`, `truemoney`, `meinchat_plus` (4) — all `<plugin_id>_*`.

## 5. Implementation notes & risks

- **`booking` + `discount` have NO `migrations/` dir** (0 versions). Their tables are created by `create_all()` (dev) / the legacy monolith `vbwd_001` (prod). A rename needs a **new per-plugin migration** registered in `alembic.ini version_locations`, and the prod monolith still emits the old name — so the rename migration must be **idempotent / guard with `_table_exists`** ([[project_migration_graph_fragmentation]] lesson). taro has 2 migrations, meinchat 9.
- **Each rename =** `ALTER TABLE <old> RENAME TO <new>` **+** update `__tablename__` **+** every `ForeignKey("<old>.id")` string **+** SQLAlchemy `relationship`/`backref` **+** any raw SQL **+** rename dependent **indexes/constraints/sequences** (Postgres does *not* auto-rename `ix_<old>_*` / `<old>_pkey`).
- **Revision-id length:** keep new migration revision ids **≤ 32 chars** (the stock `alembic_version.version_num` is `VARCHAR(32)`) — see [report 21](../../20260528/reports/21-localhost-meinchat-demo-and-protocol-500-fix.md).
- **Plugins live in their own repos** — each rename ships via the plugin's standalone repo + its own CI green ([[feedback_plugins_always_in_own_repos]]).
- **Deploy** reaches vbwd.cc only via the GitHub workflow ([[feedback_deploy_github_only]]), currently blocked at the SSH step.

## 6. Recommended sequencing (low → high risk)

1. **meinchat** `token_transfer` / `user_contact` / `user_nickname` (0 FKs) — trivial, do first.
2. **taro** `arcana → taro_arcana` (1 FK).
3. **meinchat** `conversation` (2 FK), `message` (4 FK) — update `meinchat_attachment` FK + repos in lockstep.
4. **discount** `coupon`/`coupon_usage`/`discount` (after the discount-vs-discounts decision).
5. **booking** `booking → booking_reservation` (7 internal FKs).
6. **subscription** (`vbwd_*` → `subscription_*`) — **separate, coordinated sprint** (cross-plugin ghrm FK) or keep-as-documented-exception.

## Summary count
- ✅ compliant: core (22) + ~10 plugins.
- 🔧 rename: **11 orphan tables** in booking/taro/meinchat/discount.
- ⚠ decide: discount↔discounts prefix; subscription `vbwd_*` legacy.
- 🟡 minor: 2 toss tables.
