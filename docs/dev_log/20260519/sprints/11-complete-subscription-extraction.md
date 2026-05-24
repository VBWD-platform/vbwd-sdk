# Sprint 11 — Complete the subscription extraction (models + FK leave core)

**Phase:** 3 (the deferred "A2") · **Repos:** `vbwd-backend` (+ its
`plugins/{subscription,stripe,paypal,yookassa,taro,analytics,ghrm}`),
`vbwd-fe-admin`, `vbwd-fe-user`
**Effort:** XL (~6–9 dev-days incl. a prod DB-migration window) ⚠
**Depends on:** the completed extraction (reports 02, 04, 05, 06)
**Engineering requirements:** [`_engineering-requirements.md`](./_engineering-requirements.md) — binding (E1–E6).
**Supersedes:** decision **A** (models stay in core) · **resolves R3 + R4.**

> **Goal (the user's principle, made true):** core retains **only** the abstract
> entities every plugin shares — `user`, `user_details`, `token*`, `invoice`,
> `invoice_line_item`. Subscription becomes a fully self-contained plugin peer of
> booking / shop / ghrm: it **owns its model classes and its FK to invoices**.
> No subscription type, FK, or import remains anywhere in core.

---

## Why this sprint exists

Reports 02/06 left a deliberate, documented concession: the 5 subscription model
classes + an `invoice.subscription_id`/`invoice.tarif_plan_id` FK stay core
because **6 plugins reach into the models the wrong way**. That is an *unfinished
inversion*, not an inherent coupling. This sprint finishes it.

**Measured couplings to clear (report 06 §1 + live grep):**

| # | Coupling (today) | Direction | Clean target |
|---|---|---|---|
| C1 | `stripe`/`paypal`/`yookassa` webhooks call `container.subscription_repository()` + import `Subscription`/`AddOnSubscription` to flip status on recurring payments | payment→subscription (wrong) | payment plugin emits an event; subscription plugin **handles** it |
| C2 | `taro`/`analytics` `import Subscription` to read the user's plan | consumer→subscription (wrong) | use the existing `IEntitlementProvider` port |
| C3 | `ghrm` imports `TarifPlan` + `TarifPlanCategory` (+ assoc table) | ghrm→subscription (wrong) | new **plan-catalog read port** the subscription plugin implements |
| C4 | core `invoice` table has `subscription_id` + `tarif_plan_id` FK columns | core→subscription (wrong) | invoice is generic; the subscription plugin owns the link (plugin→core) |
| C5 | `vbwd/models/__init__.py` imports the 5 subscription models to register them | core registration | the plugin registers its own models |

---

## Definition of done

1. No core module (`vbwd/`) imports or declares any subscription/plan/addon
   model, FK, column, or type. Verified by the flipped backend oracle.
2. `stripe`/`paypal`/`yookassa`/`taro`/`analytics`/`ghrm` contain **zero**
   `from vbwd.models.{subscription,tarif_plan,addon,…}` imports and **zero**
   `container.{subscription,tarif_plan,addon}_repository()` calls.
3. The 5 model classes + their tables live under `plugins/subscription/`
   (models in the plugin package; tables in the plugin's Alembic branch, A1).
4. `invoice` / `invoice_line_item` are subscription-agnostic (no `subscription_id`
   / `tarif_plan_id`); the subscription↔invoice relationship is owned by the
   plugin, with existing data migrated, **no data loss**.
5. FE: the invoice "Subscription Info" UI is plugin-contributed (core invoice
   views show only generic line items); `/deletion-info` returns a generic
   `dependencies[]`.
6. All three agnosticism oracles updated to assert the **new** contract
   (models gone from core) and green; full suites green in all repos.
7. Live-validated end to end: paid Stripe checkout → recurring renewal →
   cancellation → entitlement read (taro) → ghrm plan gate — all still work.

---

## Slices (ordered; each is behaviour-preserving, E2)

Each slice opens with its **E1 baseline** (characterisation test capturing
current behaviour) and closes with the **oracle assertion it flips**.

### S1 — Payment plugins → event-driven (clear C1) · L
- **Baseline (E1):** characterise the current recurring-payment behaviour — a
  Stripe `invoice.payment_succeeded`/`payment_failed` webhook flips the matching
  `Subscription` to ACTIVE/PAST_DUE (assert via the existing webhook tests).
- **Change:** move the subscription-status-update logic out of
  `stripe/paypal/yookassa` webhook handlers into the **subscription plugin** as
  handlers for the payment domain events the providers already `emit()`
  (`PaymentCapturedEvent`, a new `RecurringPaymentReceived/Failed` if needed,
  keyed by `provider_subscription_id`/`invoice_id`). Payment plugins keep only
  invoice + provider-session logic.
- **DIP:** payment plugins depend on the event bus (core), not on the
  subscription repo/model.
- **Verify (E2):** the baseline webhook behaviour is identical (same status
  transitions), now driven through the event handler. e2e: a real renewal still
  activates the subscription.
- **Oracle slice:** `stripe/paypal/yookassa` import no subscription model and
  call no subscription repository.

### S2 — Entitlement consumers → port (clear C2) · S
- **Baseline (E1):** capture taro/analytics behaviour that reads `Subscription`
  (e.g. "user on plan X gets feature Y / usage limit Z").
- **Change:** replace `from vbwd.models.subscription import Subscription` with
  the existing `IEntitlementProvider` (and, if needed, extend it with the narrow
  read the consumer actually needs — e.g. `current_plan_slug(user_id)`).
- **Verify (E2):** same entitlement decisions; with the subscription plugin
  disabled, the default-allow (D3) path holds.
- **Oracle slice:** `taro`/`analytics` import no subscription model.

### S3 — ghrm → plan-catalog read port (clear C3) · M ⚠ (trickiest)
- **Baseline (E1):** capture what ghrm reads from `TarifPlan`/`TarifPlanCategory`
  (which plan/category gates which repo access).
- **Design:** introduce a narrow **catalog read port** in core
  (`vbwd/services/catalog_read_model.py` — `ICatalogReadModel` with only the
  methods ghrm needs, e.g. `plans_in_category(slug)`, `plan_by_slug(slug)`), with
  a null default; the subscription plugin registers the implementation on enable
  (mirrors `ISubscriptionReadModel`).
- **Change:** ghrm consumes the port; drop the model imports + the assoc-table
  import.
- **Verify (E2):** ghrm repo-access gating unchanged; ghrm works with the
  subscription plugin disabled (null port → no plan gating).
- **Oracle slice:** `ghrm` imports no `tarif_plan*` model.

### S4 — Invoice de-couple + data migration (clear C4) · L ⚠⚠ **prod risk**
- **Baseline (E1):** characterise that the plugin can list "invoices for
  subscription S" and "invoices for plan P" (today via `invoice.subscription_id`
  / `tarif_plan_id`). Snapshot counts on a copy of prod data.
- **Change:**
  1. Add a plugin-owned link (e.g. `subscription_invoice` table, or
     `subscription_id` on a plugin billing record) in the subscription plugin's
     Alembic branch.
  2. **Data migration:** copy existing `invoice.subscription_id` /
     `tarif_plan_id` into the plugin-owned link (subscription line items already
     carry `catalog_item_id` = plan id, so plan linkage is derivable).
  3. Drop `subscription_id` + `tarif_plan_id` columns from the core `invoice`
     table; remove them from `Invoice.to_dict()`.
  4. Repoint the plugin's "invoices for subscription" queries at the new link.
- **DIP/Liskov:** core invoice behaviour for token/generic invoices is
  unchanged; only the subscription projection moves.
- **Verify (E2):** before/after row counts match; the plugin returns the same
  invoice lists; token + generic invoices unaffected.
- **Gate:** **DB backup + maintenance window**; run on a prod-data copy first;
  reversible down-migration written and tested.
- **Oracle slice:** `Invoice` model + `to_dict()` contain no `subscription`/
  `tarif_plan` reference.

### S5 — Move the 5 model classes core → plugin (clear C5) · M
- **Pre-req:** S1–S4 done (no importer, no FK left).
- **Change:** move `subscription`, `tarif_plan`, `addon`, `addon_subscription`,
  `tarif_plan_category` from `vbwd/models/` into
  `plugins/subscription/subscription/models/`; remove them from
  `vbwd/models/__init__.py`; the plugin registers its models (so
  `create_all`/Alembic autogenerate still see them). Tables already live in the
  plugin's Alembic branch (A1) — no table move, only class relocation.
- **Verify (E2):** full backend suite + the 6 now-decoupled plugins green;
  `make test` and an integration boot green.
- **Oracle slice:** importing `vbwd.models.subscription` raises; `vbwd/models`
  exports none of the 5.

### S6 — FE follow-through (invoice + deletion) · M
- **Backend:** `/admin/users/:id/deletion-info` returns a generic
  `dependencies: [{type,count,label}]` array (plugins contribute their counts);
  drop the hard-coded `subscription_count`/`invoice_count` shape.
- **fe-admin / fe-user:** the invoice "Subscription Info" block moves to a
  plugin-contributed **`invoiceDetailSections`** extension point (new, mirrors
  `userDetailsSections`); core invoice views render only generic line items.
  `Users.vue` bulk-delete dialog renders the generic `dependencies[]`.
- **Verify (E2):** invoice detail still shows subscription info **when the
  plugin is enabled**; nothing when disabled. e2e on :8080 / :8081.
- **Oracle slice:** core invoice views + `users` store contain no
  `subscription_*` field.

### S7 — Flip the oracles + decision log · S
- Update `tests/unit/test_subscription_agnostic_backend.py`: **delete** the
  `test_subscription_models_stay_in_core_per_decision_A` assertion; **add**
  assertions that the 5 models are absent from `vbwd.models` and that the 6
  plugins import none. Same flip for the two FE oracles (invoice metadata now
  gone from core).
- Update report 02 decision log: **A → superseded by Sprint 11**, **R3/R4 →
  resolved**. Update report 06 §5 (residual table → empty/closed).
- **Oracle slice:** the whole programme's exit gate now encodes the *fully*
  agnostic contract.

### S8 — (Stretch, optional) permission namespace · S
- Rename the core token/invoice permissions out of the `subscription.*`
  namespace (`token.*`, `invoice.*`) so even the permission strings are
  subscription-free. Backend permission seed + a data migration for existing
  grants. Cosmetic; can ship separately.

---

## Dependency graph

```
S1 ─┐
S2 ─┼──► S4 (migration) ──► S5 (move models) ──► S7 (flip oracles)
S3 ─┘                                   └──► S6 (FE) ──┘
S8  (independent, optional, anytime)
```
- **S1/S2/S3 parallel** — independent inversions, each removes one plugin family's
  coupling.
- **S4 before S5** — the model can't leave core while the core invoice table FKs
  reference it.
- **S5 before S7** — flip the "models stay" oracle only once they've moved.
- **S6 after S4** — the FE invoice change follows the backend DTO change.

## Risk & rollback

- **S4 is the only irreversible-ish step.** Mitigation: write + test the down-
  migration; dry-run on a prod-data copy; take a backup; run in a window; keep
  the dropped columns for one release as nullable-unused before hard-drop
  (expand/contract) if extra caution is wanted.
- **S1 touches live payment webhooks.** Mitigation: characterisation tests first
  (E1), then e2e a real renewal + a failed payment before/after.
- Everything else is behaviour-preserving relocation (E2) guarded by the oracles.

## Out of scope / stop-points

- This is the *optional clean-up* phase. The current state (reports 02/06) is
  functionally complete and CI-fenced; Sprint 11 buys **architectural purity +
  booking-only/shop-only installs**, not new features. It can be scheduled
  deliberately (esp. the S4 window) rather than rushed.
- E5 (plugins in their own repos) is unchanged — work lands in the existing
  plugin dirs, committed to `main`, no temp branches.
