# Report — Sprint 11 day 2 (cont.): S6 (FE) + S7 (oracles + decision log) COMPLETE

**Date:** 2026-05-25
**Builds on:** [report 02 — backend complete](02-sprint11-day2-backend-complete.md).
**Result:** the FE follow-through and the agnosticism-oracle flip are done.
Sprint 11 is functionally complete (optional S8 permission-namespace deferred).

---

## 1. S6 — FE follow-through

### S6-A · fe-admin invoice agnosticism
- New extension point `invoiceDetailSections` on
  `vue/src/plugins/extensionRegistry.ts` (mirrors `userDetailsSections`):
  `AdminExtension.invoiceDetailSections?: Component[]` + `getInvoiceDetailSections()`.
- The "Subscription Info" block moved out of core
  `vue/src/views/InvoiceDetails.vue` into
  `plugins/subscription-admin/src/components/InvoiceSubscriptionSection.vue`
  (receives `:invoice`), registered in the plugin's `activate()` via
  `invoiceDetailSections`. Core renders plugin sections generically
  (`<component :is="Section" :invoice="invoice" />`).
- Core `vue/src/stores/invoices.ts`: dropped `subscription_id` + all
  `plan_*` / `subscription_*` fields from the invoice DTOs.
- Test: `plugins/subscription-admin/tests/unit/InvoiceSubscriptionSection.spec.ts`.

### S6-B · fe-user invoice agnosticism
- Core `vue/src/stores/invoices.ts`: dropped `tarif_plan_id` + `subscription_id`
  from the `Invoice` interface (no fe-user view displayed them — backend no
  longer sends them after S4).

### S6-C · generic deletion dependencies
- Backend: new `vbwd/services/deletion_dependency_registry.py` (keyed
  register / unregister / resolve). `/admin/users/<id>/deletion-info` now
  returns `dependencies: [{type, count, label}]` — core contributes `invoice`,
  the subscription plugin registers a `subscription` provider in `on_enable`
  (unregistered in `on_disable`). Core names no plugin domain.
- fe-admin: `stores/users.ts` `DeletionInfo` carries a generic
  `dependencies[]`; `views/Users.vue` bulk-delete renders it generically.
- Test: `tests/unit/test_deletion_dependency_registry.py`.

## 2. S7 — oracles + decision log
- **Backend** `tests/unit/test_subscription_agnostic_backend.py`: (day-2 AM)
  flipped to assert models-left-core; (now) added
  `test_core_deletion_info_is_generic`.
- **fe-admin** `vue/tests/unit/subscription-agnostic.spec.ts`: residual notes
  removed; asserts core invoice store/view carry no `subscription_*`/`plan_*`/
  `tarif_plan_id`, the registry exposes `getInvoiceDetailSections`, and
  deletion-info is consumed generically (no `subscription_count`). 9 green.
- **fe-user** `vue/tests/unit/subscription-agnostic.spec.ts`: invoice-DTO D4
  residual closed; asserts core invoice store carries no
  `subscription_id`/`tarif_plan_id`. 6 green.
- **Decision log** `../../20260519/reports/02-phase0-outcome-and-locked-decisions.md`:
  added a banner — A/R3 superseded, R4 resolved, D4 invoice + deletion residuals
  closed; A2 + permission namespace (S8) remain deferred.

## 3. Validation
- fe-admin: 441 unit tests green (incl. new component test); changed files
  type-clean (pre-existing toss/truemoney vue-tsc errors are unrelated);
  changed files ESLint-clean.
- fe-user: 478 unit tests green; oracle 6 green; changed file type-clean.
  (3 pre-existing meinchat/cms e2e specs fail on missing network — unrelated.)
- backend: deletion registry + agnostic oracle + read port + model-table
  consistency green (62); app boots (plugin registers the provider); lint green.

## 4. Residual / deferred
- **S8 (optional, cosmetic):** core token/invoice permissions still use the
  `subscription.*` namespace + `/dashboard/{tokens,subscription/invoices}`
  routes. Ship separately if desired.
- **A2:** extract the initial subscription table DDL from the core monolith
  migration — prod-gated, low value, still deferred.

No commits made; all work uncommitted in the working tree.
