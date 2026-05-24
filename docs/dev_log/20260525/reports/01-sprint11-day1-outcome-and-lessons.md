# Report — Sprint 11 day 1: outcome + learned lessons (resume here)

**Date:** 2026-05-24 (carry-over for 2026-05-25)
**Sprint:** [11 — complete the subscription extraction](../../20260519/sprints/11-complete-subscription-extraction.md)
(models + FK leave core; supersedes decision A, resolves R3/R4).
**Read order tomorrow:** this report → `../sprints/README.md` → the sub-sprint
files in dependency order (S4 → S5 → S1-tests → S6 → S7).

---

## 1. TL;DR

Goal: core keeps **only** `user`, `user_details`, `token*`, `invoice`,
`invoice_line_item`; subscription becomes a fully self-contained plugin peer.

| Slice | State |
|---|---|
| S2 — taro/analytics → ports | ✅ **done + tested** |
| S3 — ghrm → catalog read port | ✅ **done + tested** (runtime; seed import defers to S5) |
| S1 — payment plugins → port + line-item registry | ✅ **code done + proven**; ⚠ **webhook tests red** (churn) |
| S4 — invoice FK removal + migration | ⛔ **not started** (high blast radius — investigated) |
| S5 — move 5 model classes core→plugin | ⛔ **not started** (FK-blocked by S4) |
| S6 — FE follow-through | ⛔ not started |
| S7 — flip the 3 oracles + docs | ⛔ not started |

**Verification of the done work:** 58 targeted tests green, the app boots
(agnostic oracle passes), payment plugins import zero subscription models,
flake8/black clean. **CI is red** on the ~40–50 payment-webhook tests that still
mock the old seam (see §4).

---

## 2. What landed (with file pointers)

### S2 — entitlement + read-model ports
- `vbwd/services/entitlement.py`: added `get_feature_value(user_id, name, default)`
  + `current_plan_name(user_id)` (abstract + default-None impl).
- `vbwd/services/subscription_read_model.py`: added `active_subscription_count()`.
- Impls in `plugins/subscription/subscription/services/{subscription_entitlement_provider,subscription_read_model}.py`.
- Consumers: `plugins/taro/src/routes.py` (plan limits + plan name via the
  entitlement port — no `Subscription` import); `plugins/analytics/src/routes.py`
  (active-sub count via the read-model port).
- Tests: `tests/unit/test_entitlement_port.py`, `tests/unit/test_subscription_read_model_port.py`.

### S3 — catalog read port (ghrm)
- New `vbwd/services/catalog_read_model.py` (`ICatalogReadModel`:
  `category_labels_by_slugs`, `plan_ids_in_category`; null default).
- Impl `plugins/subscription/subscription/services/catalog_read_model.py`,
  registered in the subscription plugin `on_enable`.
- Consumers: `plugins/ghrm/src/routes.py` (categories) +
  `plugins/ghrm/src/repositories/software_package_repository.py` (category filter
  via `plan_ids_in_category` instead of a JOIN to the catalog tables).
- Test: `tests/unit/test_catalog_read_model_port.py`.
- **Residual:** `plugins/ghrm/src/bin/populate_ghrm.py` still imports
  `vbwd.models.tarif_plan*` (a dev seed that *creates* plans) — repoint to the
  plugin in **S5**.

### S1 — payment plugins via lifecycle port + extensible recurring registry
- New `vbwd/services/subscription_lifecycle.py` (`ISubscriptionLifecycle`:
  `link_provider_subscription`, `record_provider_renewal`,
  `cancel_by_provider_subscription_id`, `mark_provider_payment_failed`,
  `mark_invoice_payment_failed`; no-op null default). Impl
  `plugins/subscription/subscription/services/subscription_lifecycle.py`,
  registered in `on_enable`.
- **Recurring-vs-one-time moved into the extensible line-item registry**
  (`vbwd/events/line_item_registry.py`): new `RecurringBillingSpec` dataclass +
  `recurring_billing_spec(line_item)` on `ILineItemHandler` + the registry.
  `SubscriptionLineItemHandler.recurring_billing_spec` implements it.
- `plugins/{stripe,paypal,yookassa}/.../routes.py`: webhooks now call the
  lifecycle port; recurring checkout setup
  (`_build_stripe_subscription_items` / `_get_or_create_paypal_plan`) uses
  `line_item_registry.recurring_billing_spec`. **Zero subscription-model
  imports** in all three.
- Proof tests (the user's explicit ask): `tests/unit/test_recurring_line_item_registry.py`
  (registry extensibility + custom line-item type) + `plugins/subscription/tests/unit/test_subscription_recurring_spec.py`
  (ghrm subscription mode + add-on recurring/one-time).

---

## 3. Architecture decisions made (binding for the rest)

1. **Ports for read couplings, a lifecycle port for write couplings.** taro/
   analytics/ghrm read via narrow ports (entitlement / read-model / catalog).
   Payment webhooks write via `ISubscriptionLifecycle`. All have null defaults
   so a subscription-free install degrades gracefully (D3 spirit).
2. **Recurring-ness is decided by the line-item registry, not the payment
   plugin** (user directive). A payment plugin asks the registry per line item;
   each plugin's handler declares whether its line-item type recurs +
   supplies a `RecurringBillingSpec`. **Any plugin can add its own recurring
   line-item type** — proven by test.
3. **Add-ons can be recurring** — `AddOn.is_recurring == (billing_period !=
   ONE_TIME)`. Behaviour preserved exactly: recurring add-ons recur, ONE_TIME
   add-ons are charged once. Tokens/shop are one-time (their handlers return
   no spec).

---

## 4. Open issues / what's RED

- **Payment-webhook tests (~40–50) are red.** They mock the *old*
  `container.subscription_repository()` seam the webhooks no longer use. They
  must be rewired to assert the lifecycle port (register a fake
  `ISubscriptionLifecycle` / patch `resolve_subscription_lifecycle`). Behaviour
  is unchanged — this is pure test churn. → sub-sprint `s1-finish-payment-webhook-tests`.
- **Pre-existing, NOT ours:** `plugins/paypal/tests/test_sdk_adapter.py` (15
  errors) — `PayPalSDKAdapter` doesn't implement the base
  `release_authorization` abstractmethod. Independent of this sprint.

---

## 5. Learned lessons (the important ones for tomorrow)

1. **S4 and S5 are inseparable (R4).** Core `invoice` has
   `ForeignKey("vbwd_subscription.id")` + `"vbwd_tarif_plan.id")` (string refs).
   Moving the model classes out (S5) while core still FKs them risks SQLAlchemy
   **mapper-config failure at boot** for a subscription-free deploy. Do S4
   (drop the FK) first/together. **Do not move models without removing the FK.**
2. **S4 reaches into CORE, not just the plugin.** `invoice.subscription_id` /
   `tarif_plan_id` are *written* in core `vbwd/services/invoice_service.py`
   (`create`) and `vbwd/routes/admin/invoices.py` (duplicate), plus 4 plugin
   sites (checkout_handler, subscription_service, demo_seed, lifecycle). S4 =
   change the core invoice `create` API + every caller + Alembic drop + full
   checkout/renewal/admin re-validation. Budget it as the real "A2".
3. **The subscription↔invoice link is derivable from line items** (item_type
   SUBSCRIPTION, item_id = subscription id). So the columns aren't needed:
   reroute `find_by_subscription` + renewal/checkout to the line-item link.
   Only legacy invoices lacking a subscription line item would need a backfill.
4. **Recurring determination belongs in the registry, not the payment plugin.**
   First S1 attempt put `recurring_item_billing` on the subscription lifecycle
   port (only the subscription plugin could answer). The user corrected this →
   the line-item registry already had `is_recurring_line_item`; extending it
   with `recurring_billing_spec` makes it extensible to *any* plugin. Lesson:
   prefer the existing extensible registry over a domain-specific port for
   anything other plugins might extend.
5. **Validate the FULL runtime path when extracting** (carried from report 04 —
   the DI-provider bug). The earlier extraction broke checkout + payments
   because it was only validated for login/cms/ghrm. For S4/S5, run the agnostic
   oracle + subscription integration after **each** step.
6. **Don't leave a half-done schema slice in core.** The partial S4
   `find_by_subscription` reroute was reverted so core stays consistent (the
   line-item query and the column query can diverge for legacy rows). Land S4
   as one complete, validated change.
7. **Payment code + DB migrations are the high-cost-of-error zone.** Worth the
   slower, validate-as-you-go cadence; do not batch.

---

## 6. Verification commands (resume sanity check)

```bash
cd vbwd-backend
# done-work sanity (should be green):
docker compose run --rm test pytest \
  tests/unit/test_subscription_agnostic_backend.py \
  tests/unit/test_recurring_line_item_registry.py \
  tests/unit/test_entitlement_port.py tests/unit/test_catalog_read_model_port.py \
  tests/unit/test_subscription_read_model_port.py \
  plugins/subscription/tests/unit/test_subscription_recurring_spec.py -q
# the red set (S1 churn to fix):
docker compose run --rm test pytest plugins/stripe/tests plugins/paypal/tests plugins/yookassa/tests -q
```

No commits were made (standing instruction). All work is uncommitted in the
working tree across `vbwd-backend` + its plugin repos.
