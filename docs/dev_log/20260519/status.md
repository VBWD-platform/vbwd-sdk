# 2026-05-19 — Status: Subscription extraction (Direction A)

Complete the 2026-03-27 extraction so **subscription** is a plugin peer of
shop/booking/ghrm and core is provably subscription-agnostic.
**Authoritative record:** [`reports/02-phase0-outcome-and-locked-decisions.md`](reports/02-phase0-outcome-and-locked-decisions.md)
(§3a–§3k). Engineering rules:
[`sprints/_engineering-requirements.md`](sprints/_engineering-requirements.md).

## Sprint index

| # | Sprint | Status |
|---|--------|--------|
| 01 | [backend: delete dead subscription code](done/01-backend-delete-dead-subscription-code.md) | ✅ Done |
| 02 | [frontend: delete dead duplicate views](done/02-frontend-delete-dead-duplicate-views.md) | ✅ Done |
| 03+04 | [merged: decouple core + relocate (S1–S7)](done/03-merged-decouple-core-and-relocate-subscription.md) | ✅ Done (backend) · supersedes [03](sprints/03-backend-plugin-owns-models-and-migration.md)/[04](sprints/04-backend-break-live-couplings.md) |
| 05 | [backend: email templates → plugin](done/05-backend-email-templates-to-plugin.md) | ✅ Done |
| 06 | [fe-core: purge subscription](done/06-fe-core-purge-subscription.md) | ✅ Done |
| 07 | [fe-user: nav + i18n](done/07-fe-user-de-hardcode-nav-router-i18n.md) | ✅ Done (e2e-verified) |
| 08 | [fe-admin: P1 + P2](done/08-fe-admin-resolve-live-couplings.md) | ✅ Done (P1 + P2, e2e-verified) |
| 09 | [cross-repo agnostic-install gate](sprints/09-cross-repo-agnostic-install-proof.md) | ✅ Backend + fe-admin + **fe-user** oracles done (in CI) |
| 10 | fe-user: extract checkout subscription/shop coupling (source registry) | ✅ Done (e2e-verified) — see report §3o |
| 11 | [complete extraction: models + FK leave core (resolves R3/R4, supersedes A)](sprints/11-complete-subscription-extraction.md) | 📋 Planned — optional "full clean" phase (XL, incl. DB-migration window) |

## Work done

- **Backend extraction COMPLETE** (merged Sprint 03, S1–S7) — core owns no
  subscription routes / repos / services / DI / feature-gating / line-item
  coupling / seeder imports. Generic ports added: `IEntitlementProvider`
  (S3, D3 config-flag/allow), `ISubscriptionReadModel` (S4), line-item
  registry resolve/recurring (S1/S5a), demo-data registry (S5b). **Live-
  validated** in the running app (login/permissions/cms/ghrm all serve).
- **S6 model relocation CANCELLED → decision (A):** the 5 model classes stay
  in core as shared domain (6 plugins depend on them — R3). **S7 → (A1):**
  plugin owns its Alembic migration branch (`20260523_1000_sub_baseline`),
  single head, clean `upgrade`.
- **fe-core (06):** dead subscription store/composable/`FeatureGate`/
  `UsageLimit`/`SUBSCRIPTION_*` events removed; `CartItemType` generalised;
  build green, dist regenerated.
- **fe-user (07):** subscription nav group → `userNavRegistry`
  (plugin-owned); Invoices = core top-level (decision (i)); subscription
  i18n moved to the plugin across 8 locales. e2e-verified on :8080.
- **fe-admin (08 P2):** plugin→core `@/stores`/`@/components` imports
  inverted (plugin owns its copies); dead core copies deleted. **AdminTopbar
  titles → route meta** (P1 piece).
- **fe-admin (08 P1) — DONE & e2e-verified:** new extension points
  `userEditTabs`, `accessLevelUserColumns`, `AccessLevelFormField.fields`
  (+ reused `userDetailsSections`). `UserEdit` Subscriptions/Add-ons tabs,
  `UserDetails` subscription summary, AccessLevels "Linked Plan" column, and
  the Access-Level form's `linked_plan_slug` load/save all moved to the
  subscription-admin plugin. **Core `stores/subscriptions.ts` deleted** (last
  live coupling). `UserCreate` status no longer borrows a subscription i18n
  key. Live-verified on :8081 incl. an edit-form save round-trip. See report
  §3m. Admin e2e harness: localStorage needs **both** `admin_token` and
  `admin_token_user`.
- **fe-admin (09 FE oracle) — DONE:**
  `vue/tests/unit/subscription-agnostic.spec.ts` (7 assertions) CI-gates the
  contract.
- **fe-user (Sprint 10 + 09 FE oracle) — DONE & e2e-verified:** core
  `stores/checkout.ts` made generic via a new `checkoutSourceRegistry`;
  subscription + shop each register a `CheckoutSource` (with their own summary
  component) — core checkout names no plugin domain. `PublicCheckoutView`
  generic; subscription `Checkout.vue` uses the revived plugin store. Core
  checkout test relocated to the subscription plugin (12); new generic core
  store test (8); fe-user oracle (5). Live-verified on :8080 (plan checkout,
  shop source matching, dashboard checkout). See report §3o. (Vite/bind-mount
  HMR needed a dev-container restart — Sprint 07 gotcha.)
- **CI gate (09 backend):** `tests/unit/test_subscription_agnostic_backend.py`
  (29 assertions) fences the whole backend contract; runs in `make test`.
- **Email (05):** core `email_service` made subscription-agnostic — the 4
  subscription/payment send methods + `renewal_reminder` + their default
  subjects removed; the 5 templates moved to the plugin; generic
  `register_template_path` (ChoiceLoader) added; plugin handlers send via the
  generic `send_template`. Stale core email tests removed.

## Verification

Backend unit **804/4**, fe-user unit **477** (incl. 5-assertion fe-user
agnosticism oracle; +12 relocated subscription checkout-store, +8 generic core
checkout), fe-admin core unit **294** (incl. 7-assertion oracle) +
subscription-admin plugin **108**, fe-core build green + guard 9, lint clean
throughout. All slices behaviour-preserving (E2 — except the intentional
removal of the duplicate UserEdit linked-plan badge, now canonical on
AccessLevels); no commits made (standing instruction).

## Remaining

The subscription extraction (Direction A) is **functionally complete** across
backend, fe-core, fe-admin, and fe-user. Optional hardening only:

- **Sprint 09 hardening (optional)** — plugin-disabled runtime proof + wire the
  three `subscription-agnostic` oracles (backend, fe-admin, fe-user) as named
  per-repo CI jobs.
- **fe-admin / fe-user further-decoupling (optional, D4-acceptable)** —
  `InvoiceDetails`/`InvoiceDetail` "Subscription Info" behind an
  `invoiceDetailSections` point; `/deletion-info` generic `dependencies[]`
  (backend); `Dashboard` token/invoice gates use the `subscription.*` permission
  namespace. All D4-residual (tokens/invoices stay core), not blocking.

## Pending — needs user action

- **Commit & push** across `vbwd-backend`, `vbwd-fe-core`, `vbwd-fe-user`,
  `vbwd-fe-admin` + the standalone plugin repos (all work is uncommitted).
- **fe-core → fe-user/fe-admin submodule pin bump** so they consume the
  purged `dist/` (06). Not blocking 07/08 (deleted symbols had no consumers).
- **Prod DB:** S7 baseline migration is a no-op (`alembic upgrade head`) —
  zero data risk; a backup/window is only needed if A2 (full table
  extraction from the monolith) is ever undertaken.

## Blockers

None. Decisions locked: D1–D4, R1, R2, R3=(A), R4=(A1), S07=(i), S08-P2=(a).
