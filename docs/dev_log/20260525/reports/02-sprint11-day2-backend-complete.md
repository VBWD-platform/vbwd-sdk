# Report — Sprint 11 day 2: backend extraction COMPLETE (S4 · S5 · S1-tests · S7-backend)

**Date:** 2026-05-25
**Sprint:** [11 — complete the subscription extraction](../../20260519/sprints/11-complete-subscription-extraction.md)
**Builds on:** [day-1 report](01-sprint11-day1-outcome-and-lessons.md) (S2/S3 done, S1 code done).

---

## 1. TL;DR

The whole **backend** half of the sprint landed today. Core now keeps only
`user`, `user_details`, `token*`, `invoice`, `invoice_line_item`; the 5
subscription model classes live in the plugin; the core invoice carries no
subscription/plan FK; and all payment-plugin tests are green.

| Slice | State |
|---|---|
| S4 — invoice FK removal + migration | ✅ **done + validated** (upgrade/downgrade/re-upgrade on live data) |
| S5 — move 5 model classes core→plugin | ✅ **done** (app boots, mapper config OK) |
| S1-tests — rewire payment webhook tests | ✅ **done** (199 stripe/paypal/yookassa tests green) |
| S7 — backend agnosticism oracle | ✅ **flipped + green** (FE oracles still pending S6) |
| S6 — FE follow-through | ⛔ not started (next) |
| S7 — FE oracles + decision log | ⛔ not started (after S6) |

Backend `bin/pre-commit-check.sh --full` is the gate. No commits made
(standing rule).

---

## 2. What landed (with file pointers)

### S4 — core invoice de-coupled from subscription/plan
- **Model:** `vbwd/models/invoice.py` — dropped `subscription_id` + `tarif_plan_id`
  columns + their `to_dict` keys. Removed the now-dangling relationships
  `Subscription.invoices` + `TarifPlan.invoices` (unused; backrefs gone).
- **Read reroute:** `vbwd/repositories/invoice_repository.py::find_by_subscription`
  now JOINs `InvoiceLineItem` (item_type SUBSCRIPTION, item_id == subscription
  id). `subscription_read_model.enrich_invoice` derives the subscription from
  the line item too (then plan via `subscription.tarif_plan`).
- **Writers (stopped writing the columns; all create/keep a SUBSCRIPTION line
  item so the link survives):** core `invoice_service.create_invoice` (params
  dropped — no production callers), core `admin/invoices.py` duplicate (now
  copies line items), plugin `checkout_handler`, `subscription_lifecycle`
  renewal, **plus two that previously had NO line item and now add one** —
  `subscription_service.expire_trials` and `admin_subscriptions` admin-create.
- **Migration:** `alembic/versions/20260525_1000_inv_drop_sub_fk.py` (a **core**
  migration — the column drop must run even subscription-free). Upgrade
  backfills a SUBSCRIPTION line item for any legacy column-only invoice, then
  drops the FKs + columns; downgrade re-adds them and backfills from the line
  item (guarded by `EXISTS` against a live subscription).
- **Tests:** `tests/unit/test_invoice_decoupled_from_subscription.py`,
  `plugins/subscription/tests/integration/test_invoice_subscription_link.py`,
  `plugins/subscription/tests/integration/test_expire_trials_invoice_link.py`.

### S5 — the 5 model classes left core
- `git mv` `{subscription,tarif_plan,tarif_plan_category,addon,addon_subscription}.py`
  → `plugins/subscription/subscription/models/`. Fixed the one intra-set
  TYPE_CHECKING import; flipped the plugin `models/__init__.py` to define
  locally; removed the 5 (+ assoc tables) from `vbwd/models/__init__.py`.
- Removed the core→plugin `User.subscriptions` relationship (unused; user
  deletion still cascades via the DB-level `ondelete=CASCADE` on
  `vbwd_subscription.user_id`).
- Repointed the seed importers: `plugins/ghrm/src/bin/populate_ghrm.py`,
  `bin/install_demo_data.py`, and the plugin's own lazy imports in
  `subscription_read_model` + `catalog_read_model`.

### S1-tests — payment webhooks assert the port, not the repo
- Each plugin's `conftest.py` gained `fake_lifecycle` (a `MagicMock(spec=
  ISubscriptionLifecycle)` registered via `register_subscription_lifecycle`)
  and `recurring_registry` (a fake `ILineItemHandler` that reports a line item
  recurring iff it carries a `_recurring_spec`). Tests now assert the port call
  / registry spec instead of the removed `container.subscription_repository` /
  `payment_route_helpers.db` seams.

### S7 (backend) — oracle flipped
- `tests/unit/test_subscription_agnostic_backend.py`: deleted
  `test_subscription_models_stay_in_core_per_decision_A`; added that the 5
  model modules are gone from core, `vbwd.models` exports none of them, the
  core invoice has no subscription/plan FK, and the 6 peer plugins import no
  `vbwd.models.{the 5}`.

---

## 3. Bugs found + fixed along the way (not in the original plan)

1. **Pre-existing dirty data:** 1 of 12 SUBSCRIPTION line items in the dev DB
   has `item_id` = a *plan* id, not a subscription. The S4 downgrade backfill
   is hardened (`EXISTS` guard) so it skips this row; the migration is correct
   for all valid data. The row is historical seed cruft — code now always
   keeps the `item_id == subscription.id` invariant.
2. **paypal + yookassa routes imported the SDK adapter from the wrong path**
   (`plugins.paypal.sdk_adapter` instead of `plugins.paypal.paypal.sdk_adapter`,
   same for yookassa). Fixed — this alone unblocked most of their webhook/route
   tests.
3. **`PayPalSDKAdapter` didn't implement the base `release_authorization`**
   abstractmethod, so it couldn't be instantiated (the day-1 "15 pre-existing
   paypal adapter errors"). Added `release_authorization` delegating to the
   existing `void_authorization` — this fixed both the in-scope webhook tests
   **and** the 15 pre-existing errors. (Deviation from day-1's "don't fix here"
   note, justified: the in-scope webhook tests instantiate the adapter.)
4. **Latent S2 test gap:** `tests/unit/test_subscription_read_port.py`'s fake
   `_RM` didn't implement `active_subscription_count` (added to the port in S2)
   → completed the double.

---

## 4. Validation done
- Migration: snapshot → `upgrade` (columns dropped) → `downgrade` (11 valid
  rows restored, 1 dirty row correctly skipped) → `upgrade` (final). Verified
  against the live dev DB.
- App boot / `configure_mappers()` OK with subscription enabled.
- Backend core unit + integration + subscription plugin: green (884 passed).
- Payment plugins: 199 passed (was 66 failed + 15 errored).
- `bin/pre-commit-check.sh --lint` green.

## 5. What's next (FE — S6, then S7-FE + decision log)
- **S6** (`vbwd-fe-admin` + `vbwd-fe-user`): add an `invoiceDetailSections`
  extension point mirroring the existing `userDetailsSections`; move the
  "Subscription Info" block out of core `vue/src/views/InvoiceDetails.vue`
  into the `subscription-admin` plugin; drop `subscription_*` from core
  `vue/src/stores/invoices.ts`; make `/admin/users/:id/deletion-info` return a
  generic `dependencies[]` and update `Users.vue`.
- **S7-FE**: flip the `subscription-agnostic.spec.ts` oracles in both FE repos.
- **Decision log**: mark A superseded, R3/R4 resolved in
  `../../20260519/reports/02-phase0-outcome-and-locked-decisions.md`.

No commits made; all work is uncommitted in the working tree.
