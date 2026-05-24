# S6 — FE follow-through (invoice subscription UI + deletion deps)

**Risk:** medium. **Depends on S4** (backend stops emitting invoice
`subscription_*` once the columns are gone). Repos: `vbwd-fe-admin`, `vbwd-fe-user`.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate: the FE
agnosticism oracle + `bin/pre-commit-check.sh --full` green per repo before
"done" (extend via the `invoiceDetailSections` extension point — don't special-
case subscription in a core view).

## Backend
- `/admin/users/:id/deletion-info`: return a generic
  `dependencies: [{type, count, label}]` array (plugins contribute their counts)
  instead of the hard-coded `subscription_count`/`invoice_count` shape.

## fe-admin
- New extension point `invoiceDetailSections` on `extensionRegistry` (mirrors
  `userDetailsSections`). Move `InvoiceDetails.vue`'s "Subscription Info" block
  to a subscription-admin plugin component; core invoice view shows only generic
  line items.
- `Users.vue` bulk-delete dialog: render the generic `dependencies[]` instead of
  `subscription_count`. Drop `subscription_count` from `stores/users.ts`.

## fe-user
- Same `invoiceDetailSections` treatment for `InvoiceDetail.vue` /
  `InvoicePay.vue` subscription metadata (move to the subscription plugin).
- `stores/invoices.ts`: drop `subscription_*` / `tarif_plan_id` fields (no longer
  sent by the backend after S4).

## Acceptance
- The fe-admin + fe-user agnosticism oracles assert no `subscription_*` invoice
  field in core invoice views/stores; invoice "Subscription Info" still shows
  **when the plugin is enabled** (plugin-contributed), nothing when disabled.
- Note D4 residual now fully closed: invoices carry no subscription anything.
