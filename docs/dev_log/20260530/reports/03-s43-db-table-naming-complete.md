# Report 03 — S43 DB Table-Naming Normalization: COMPLETE

**Date:** 2026-05-31
**Sprint:** [S43 — DB table-naming normalization](../sprints/s43-db-table-naming-normalization.md)
**Audit:** [report 02](02-db-table-naming-audit.md)
**Status:** ✅ **DONE & GREEN** — all rename-caused CI breakages fixed.

## What shipped

Every bare / wrong-prefixed table renamed to its canonical owner prefix
(`vbwd_` for core, `<plugin_id>_<model>` for plugins) via **data-preserving
`ALTER TABLE … RENAME`** migrations (no drop/recreate). 18 tables across 8
plugins. Each migration is guarded + idempotent (safe on the monolith-built
prod DB, on a `create_all` dev DB, and on re-runs), so it runs on PROD through
`deploy.sh --migrate` in CI **and keeps the data**.

| Sub | Plugin | Renames |
|-----|--------|---------|
| 43.0a/b | meinchat | `token_transfer/user_contact/user_nickname/conversation/message/attachment` → `meinchat_*` |
| 43.0b lockstep | meinchat-plus | `message_delivery` FK → `meinchat_message` (dynamic-FK for fresh-DB order independence) |
| 43.1 | taro | `arcana` → `taro_arcana` (+ `taro_card_draw` FK) |
| 43.2 | discount | `coupon`→`discount_coupon`, `coupon_usage`→`discount_coupon_usage`, `discount`→`discount_rule`; class `Discount`→`DiscountRule` |
| 43.3 | booking | `booking` → `booking_reservation` |
| 43.4 | subscription | 7 tables off the core `vbwd_` prefix → `subscription_*` (`vbwd_subscription`→`subscription_record`, `vbwd_tarif_plan`→`subscription_tarif_plan`, +2 m2m assoc tables) |
| 43.4 lockstep | ghrm | `ghrm_software_package` FK → `subscription_tarif_plan` |
| 43.5 | toss-payments | `toss_cash_receipts` → `toss_payments_cash_receipts` (main `toss_payments` table kept per decision #3) |

A `test_table_naming.py` oracle was added to each touched plugin asserting the
`__tablename__` prefixes, guarding the renames against regression.

## CI fixes (this session)

After the renames, the three standalone-repo CIs that referenced **old table
names outside the model layer** went red. Two were genuine S43 misses, fixed:

1. **meinchat** — `tests/integration/test_retention_prune.py` issued raw SQL
   `SELECT count(*) FROM conversation` (bare name). → `meinchat_conversation`.
   Pushed `3bebe8f`. **Green.**
2. **subscription** — `tests/integration/test_schema_characterisation.py` froze
   a golden DDL fingerprint keyed on the old `vbwd_*` names. S43.4 is a
   *deliberate* rename sprint, so the snapshot was legitimately re-baselined:
   updated `SUBSCRIPTION_TABLES` to the `subscription_*` names and regenerated
   `_schema_fingerprint.json`. Pushed `1b06f3a`. **Green.**

## Final CI state (8 plugins)

| Plugin | CI | Note |
|--------|----|------|
| meinchat `3bebe8f` | ✅ | |
| meinchat-plus `7d707fb` | ✅ | |
| taro `65f5af7` | ✅ | |
| discount `af2bfdd` | ✅ | |
| toss-payments `38136f4` | ✅ | |
| subscription `1b06f3a` | ✅ | |
| ghrm `ee4f36b` | ✅ | |
| booking `f7adc80` | ⚠️ backend green; **E2E red** | **pre-existing, NOT S43** |

### booking E2E — pre-existing, unrelated to S43

booking's **backend** job (lint + unit + **integration**) is fully green. Only
its **Playwright E2E** job is red, with a login→dashboard `page.waitForURL`
**timeout** — the documented fe-admin e2e **auth-harness rot** (navbar became
dropdown groups; the flat `nav-*` testids are gone, and the auth seed needs
*both* `isAuthenticated` localStorage keys). This job was **already failing
before S43** (commit `340254c` "code review cleanup" and earlier all red on
e2e). The S43 change is a backend `__tablename__` rename + migration — it
touches no frontend or auth code, so it cannot have caused, and did not change,
this failure.

**Recommendation:** fix the booking fe-admin e2e auth harness (seed both
localStorage keys + navigate by URL instead of the dead `navigateViaNavbar`
helper) as a **separate** follow-up, tracked with the other fe-admin e2e
harness rot — out of scope for the table-naming sprint.

## DoD

- ✅ All bare/orphan table names eliminated (only the intentionally-kept
  `toss_payments` main table remains == its plugin id).
- ✅ Data-preserving, prod-safe, idempotent migrations (validated up/down/up).
- ✅ Python model `__tablename__` + FK strings updated; class renames done
  (`Discount`→`DiscountRule`); oracle tests added per plugin.
- ✅ Every touched plugin's backend CI green; 2 rename-caused breakages fixed.
- ⚠️ One pre-existing, unrelated booking **e2e** failure remains (separate
  follow-up).
