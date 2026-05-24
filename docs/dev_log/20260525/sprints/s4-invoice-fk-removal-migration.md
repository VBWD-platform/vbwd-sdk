# S4 — Invoice de-couple: drop the subscription/plan FK from core invoice

**Risk:** HIGH (core invoice `create` API + DB schema + boot). Run on local with
a tested down-migration. Validate after each step.
**Outcome:** core `invoice` carries no `subscription_id` / `tarif_plan_id`;
the subscription↔invoice link lives in the invoice's SUBSCRIPTION **line item**
(item_id = subscription id). Unblocks S5 (R4).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate:
`bin/pre-commit-check.sh --full` green before "done" (here: write the migration
test + the line-item-link characterisation test *first*; the down-migration is
part of the slice).

> Investigated 2026-05-24 — this is the real "A2". The columns are written in
> **core** (`invoice_service`, `admin/invoices.py`) + 4 plugin sites, so it is
> not a plugin-only change.

## Baseline (E1)
Snapshot, on a copy of representative data, that the plugin can list "invoices
for subscription S" and that checkout/renewal/admin-duplicate produce invoices
with the right linkage. Capture counts to diff after.

## The exact touch-points (from the dig)

**Reads of `invoice.subscription_id` / `tarif_plan_id`:**
- `vbwd/repositories/invoice_repository.py::find_by_subscription` (the main one).
- `vbwd/models/invoice.py::to_dict` (serialises both).

**Writes (UserInvoice(... subscription_id=, tarif_plan_id=)):**
- core `vbwd/services/invoice_service.py` (`create`, ~lines 73/76).
- core `vbwd/routes/admin/invoices.py` (~155/156, invoice duplication).
- plugin `checkout_handler.py` (~119/190/212/213) — initial checkout invoice.
- plugin `subscription_service.py` (~396).
- plugin `subscription_lifecycle.py` (renewal — the one S1 added).
- plugin `demo_seed.py` (~146).

## Steps (each validated)

1. **Reroute the read.** `find_by_subscription` → join `InvoiceLineItem`
   (item_type SUBSCRIPTION, item_id == subscription_id). (Drafted + reverted on
   2026-05-24 — re-apply as part of the *complete* change, not alone.)
2. **Stop writing the columns.** Remove `subscription_id`/`tarif_plan_id` kwargs
   from every writer above. The SUBSCRIPTION **line item** already carries
   `item_id = subscription.id` (and resolves to the plan via
   `resolve_catalog_item_id`), so the link is preserved. Confirm checkout +
   renewal both create a SUBSCRIPTION line item (they do).
3. **Core invoice `create` API.** Drop the `subscription_id`/`tarif_plan_id`
   params from `invoice_service.create` (and the admin duplicate path); update
   all callers. This is the core-API part — keep `invoice` abstract.
4. **Model + serialisation.** Remove the two columns from
   `vbwd/models/invoice.py` + `to_dict`.
5. **Alembic migration** (plugin branch per A1, or a core invoice migration —
   decide; the columns are on the core `vbwd_invoice` table, so likely a core
   migration): drop `subscription_id`, `tarif_plan_id` (+ their FKs/indexes).
   Write the reversible `downgrade`. **Backfill check:** any legacy invoice with
   `subscription_id` set but no SUBSCRIPTION line item must get a line item
   first (data migration) — query for these before dropping.
6. **Validate:** agnostic oracle + subscription integration + a real checkout +
   a renewal (via the lifecycle port) + admin invoice duplicate + app boot.

## Acceptance (the slice's oracle)
- `vbwd/models/invoice.py` + `to_dict` contain no `subscription`/`tarif_plan`.
- `grep -rn "subscription_id=\|tarif_plan_id=" vbwd/` (invoice context) → none.
- `find_by_subscription` returns the same set as before (line-item based).
- App boots; checkout/renewal/admin invoice flows unchanged.

## Notes
- FE reads `invoice.subscription_id`/`tarif_plan_id`/`subscription_*` metadata —
  that's **S6** (move the invoice "Subscription Info" display to a plugin
  `invoiceDetailSections`). Coordinate: after step 4 the backend stops emitting
  those fields.
