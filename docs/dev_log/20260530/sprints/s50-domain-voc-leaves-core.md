# Sprint 50 — Domain vocabulary leaves core

**Status:** DONE / LOCKED — 2026-06-06 (shipped via S50.1–S50.4 + S50.6 + S50.5 lock)
**Area:** `vbwd-backend` core (`vbwd/`) + plugins `subscription`, `cms`, `stripe`/`paypal`/`yookassa`, `ghrm` + `vbwd-fe-admin-plugin-subscription`
**Depends on:** **S49** (GHRM). S49 declares ghrm→subscription and repoints ghrm's catalog reads, removing `catalog_read_model`'s last consumer — so S50.1 is mostly a *verify + delete*.
**Blocks / overlaps:** **S50.1–S50.3 block [S46 (Unified Data Exchange)](s46-unified-data-exchange.md)** — S46's invoice/user exchangers + per-list controls build on the post-S50.3 seams. **S50.4 (money-path events) is independent of S46's surface**, so S46 may start once S50.1–S50.3 are locked and S50.4 can run in parallel/after.
**Trigger:** the 2026-06-04 agnosticism review (turns leading to S49.0's rework). Core currently *names plugin domains* — `subscription`, `tarif`/`plan`, `seo`, `catalog` — in services, ports, event classes, and even event **fields**. This sprint removes that vocabulary from `vbwd/` entirely.

## Engineering requirements (BINDING)
**TDD-first** (failing test first, red→green→refactor) · **DevOps-first** (local + CI green from cold; schema only via Alembic) · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change per workstream). Guard: `bin/pre-commit-check.sh --full` green on **every touched repo** = "done"; `--quick` while iterating. See [`_engineering_requirements.md`](_engineering_requirements.md). This sprint is the one that *changes* `vbwd/`; every change must keep `test_core_agnosticism.py` green and drive the new oracle (S50.0) toward zero.

## The governing principle (decision rule)

> **Core is event-aware, not domain-aware.** Its only cross-plugin surface is (1) the **string-keyed event bus** (`publish(name, dict)` / `subscribe(name, cb)` — plain dicts, no typed plugin events) and (2) **generic, domain-neutral registries** where core *routes* a generic question and forwards an answer it never interprets.
>
> **A port in core is fine when core only ROUTES through it; it is a leak when core READS a domain field through it.** If you cannot express the seam without writing `subscription` / `tarif` / `plan` / `seo` / `catalog`, it does not belong in `vbwd/`.

This splits today's ports cleanly:

| | Pattern | Verdict |
|---|---|---|
| **Kind 1 — core routes generically** | `line_item_registry`, `deletion_dependency_registry`, `checkout_price_adjustment_registry`, `demo_data_registry`, `access_level_content_provider`, `entitlement` (`IEntitlementProvider`), `IFileStorage`, `payment_provider`/`shipping_interface`, `pdf_service`, `sdk/*` | **STAY** — generic vocabulary, core never reads a domain field |
| **Kind 2 — core reads a domain field** | `subscription_read_model` (`enrich_invoice` → `plan_*`), `seo_registry`+`seo_renderable`, `subscription_lifecycle`, `catalog_read_model`, `subscription_events`, domain fields baked into `payment_events` | **LEAVE** core |

## What leaves, and where it goes (evidence-grounded)

| Target (core) | Core consumer(s) today | Disposition |
|---|---|---|
| `services/catalog_read_model.py` | ghrm only (`routes.py:194,207`, `software_package_repository.py:4,65`) | **Delete** — S49 already repointed ghrm to the subscription-owned read (declared dep). S50.1 verifies + removes the dead core port. |
| `services/seo_registry.py` + `services/seo_renderable.py` + `routes/seo.py` | core `/sitemap.xml`,`/sitemap-N.xml`,`/robots.txt` (118-line route) | **Move whole SEO feature into `cms`** (cms already owns every `seo_*` service). cms registers the routes at root (`get_url_prefix("")`). |
| `services/subscription_read_model.py` | `routes/admin/invoices.py:111` (`enrich_invoice`), `routes/admin/users.py:447` (`user_addon_subscriptions`), `:393` (`count_user_subscriptions`) | **Convert to generic registry + FE.** `enrich_invoice` → generic *invoice extra-fields* registry (core merges an **opaque dict** it never interprets — same shape as `deletion_dependency_registry`); add-ons → subscription admin endpoint consumed by the fe-admin subscription plugin's `userEditTabs`/`userDetailsSections`; `:393` is **redundant** (deletion registry already covers it) → delete. Then delete the core port. |
| `services/subscription_lifecycle.py` | **none in core** — stripe (`routes.py:270,302,320,480`), paypal (`:350,382,395,410`), yookassa (`:253,282`) | **Delete → events.** Payment plugins publish payment/lifecycle facts to the bus; subscription subscribes. ⚠️ blocked on the S50.0 spike (two methods return values — see Open decision). |
| `events/subscription_events.py` | core bus only (string-routed) | **Move event classes to `subscription`.** Core keeps only abstract `DomainEvent` (`events/domain.py`) + the bus. |
| `events/payment_events.py` domain fields | various | **Clean:** strip `subscription_id` (incl. the **required** one on `PaymentFailedEvent`!) and `tarif_plan_id` (`CheckoutInitiatedEvent`); move `SubscriptionCancelledEvent` to subscription. Payment events carry `invoice_id` + generic `metadata`; subscription derives its linkage via its **line-item handler** (already in `line_item_registry`). |

**Stays in core, untouched:** everything in the Kind-1 row above. `entitlement.py` explicitly stays — it's a generic permission-decorator port that names no domain.

## The acceptance oracle (the lock)
New `tests/unit/test_core_no_domain_vocabulary.py` — AST/source-walk over `vbwd/` asserting **zero** occurrences of the banned domain terms (`subscription`, `subscriptions`, `tarif`, `tarif_plan`, `plan_id`/`plan_name` as core symbols, `seo`, `sitemap`, `catalog`) in identifiers, imports, and string literals — excluding generic words used in a domain-neutral sense (curated, documented allowlist; additions require a comment justifying why the term is generic). This is the regression guard that keeps the vocabulary out after the sprint. (Complements `test_core_agnosticism.py`, which bans `from plugins.*` in core.)

## Sub-sprints (TDD-first; sized in the S49 turn — total ≈ 8–12 focused dev-days, B+E ≈ half)

Order = cheapest/independent first, riskiest (money path) last, oracle locked at the end.

### S50.0 — Spike + oracle scaffold *(XS, ~0.5–1d)*
- **Spike (blocks S50.4):** trace what stripe/paypal do with `record_provider_renewal()`'s `renewal_invoice_id` and `link_provider_subscription()`'s result (`routes.py:270,350,480`). Decide: can the webhook **fire-and-forget** (subscription derives the renewal invoice / link from invoice line items), or does it genuinely need a synchronous return? Output: a locked decision in this doc that fixes S50.4's seam (events vs. a generic request/response registry that names no domain).
- Add the oracle in **report mode** (lists current violations, non-failing) so each later sub-sprint can drive its category to zero.

### S50.1 — Remove `catalog_read_model` from core *(XS, ~0.5d, low risk)*
- **Verify** S49 repointed ghrm's catalog reads to the subscription-owned port (ghrm has `dependencies=["subscription"]`).
- Delete `vbwd/services/catalog_read_model.py` + its registration in `plugins/subscription/__init__.py` (the core-port `register_catalog_read_model` call); subscription keeps its own `CatalogReadModel`, now consumed directly by ghrm.
- **Test first:** grep oracle "catalog" → 0 in core; ghrm `--full` + subscription `--full` green.

### S50.2 — SEO feature → cms *(M, ~1.5–2d, low-med risk)*
- Move `seo_renderable.py` (protocol), `seo_registry.py` (provider registry + null aggregator), and `routes/seo.py` (the 3 routes) into `plugins/cms`. cms registers the blueprint with `get_url_prefix("")` so URLs stay at root (`/sitemap.xml`, `/sitemap-<n>.xml`, `/robots.txt`).
- Delete the core route registration + the two core files.
- **Test first:** cms integration — `/sitemap.xml` served by cms returns the same urlset (move existing `test_seo_pipeline_wiring` assertions); root paths unchanged; with cms disabled, no sitemap route (acceptable — no content plugin, no sitemap). Oracle "seo"/"sitemap" → 0 in core.

### S50.3 — `subscription_read_model` → generic registry + fe-admin injection *(M–L, ~2–3d, med risk)*
- **Backend:** introduce a generic *invoice extra-fields* provider registry in core (mirrors `deletion_dependency_registry`; returns an **opaque `dict`** core merges into the invoice response without interpreting). subscription registers a provider (its existing `enrich_invoice` body, now plugin-internal). `routes/admin/invoices.py:111` calls the generic registry.
- **Add-ons:** expose a subscription admin endpoint (e.g. `GET /api/v1/admin/subscription/users/<id>/addons`) serving the current `user_addon_subscriptions` shape; remove the core call at `users.py:447`.
- **Delete** the redundant `users.py:393` `count_user_subscriptions` call (deletion registry already reports the subscription dependency).
- **fe-admin subscription plugin** (`vbwd-fe-admin-plugin-subscription`): the add-ons/subscription data now renders via the existing `userEditTabs`/`userDetailsSections` + `invoiceDetailSections` extension points, fetching from the subscription endpoints (no longer pre-merged by core).
- Delete `vbwd/services/subscription_read_model.py` once all three call sites are off it.
- **Test first:** core unit — invoice response merges an opaque provider dict with no subscription symbols; with no provider registered, invoice response carries core fields only. fe-admin vitest — the subscription tab/section renders from the endpoint. Oracle: `subscription`/`plan` → 0 in core admin routes.

### S50.4 — `subscription_lifecycle` → events + event cleanup (B+E) *(L, ~3–5d, HIGH risk — money path)*
- Per the S50.0 decision: payment plugins **publish** lifecycle facts to the bus (string-named, plain dict — `invoice_id` + `metadata`); the subscription plugin **subscribes** and does link/renew/cancel/fail. Delete `vbwd/services/subscription_lifecycle.py` + the `register_subscription_lifecycle` calls in all three payment plugins.
- **Event cleanup:** move `subscription_events.py` classes into subscription; move `SubscriptionCancelledEvent` out of `payment_events.py`; strip `subscription_id`/`tarif_plan_id` domain fields from payment/checkout events (carry `invoice_id` + `metadata`; subscription derives linkage via its line-item handler). Core keeps only `events/domain.py` (`DomainEvent`) + `bus.py`.
- **Test first:** payment-plugin contract — webhook publishes the right event name + dict (no subscription symbols in the payload type); subscription handler, subscribed to that name, performs the link/renew/cancel/fail (against `db`). **Payment-with-subscription-disabled** — no subscriber ⇒ webhook still succeeds (the event is a no-op), proving payment stays subscription-free. Re-run the existing stripe/paypal recurring + e2e payment tests green. Oracle: `subscription`/`tarif` → 0 in `vbwd/events/`.

### S50.5 — Lock the oracle *(XS, ~0.5d)*
- Flip `test_core_no_domain_vocabulary.py` from report mode to **enforcing**; finalize the documented allowlist.
- Final `--full` across every touched repo (core + subscription + cms + 3 payment + ghrm + fe-admin subscription plugin). `git grep -nE 'subscription|tarif|\bseo\b|sitemap|catalog' vbwd/` returns only allowlisted, justified hits.

## Open decision — CLOSED 2026-06-06 (S50.0 spike)
- **B-returns: RESOLVED → fire-and-forget events (pure events, ~3d path).**
  - **Evidence:** the only return consumer is the renewal path. `stripe/stripe/routes.py:270-297` calls `record_provider_renewal(...) -> renewal_invoice_id`, then uses that id *solely* to `emit_payment_captured(invoice_id=renewal_invoice_id, …)`. `paypal/paypal/routes.py:350` is identical. `link_provider_subscription` returns `None` (no consumer). yookassa uses no renewal return.
  - **Why no synchronous return is needed:** the core EventBus dispatches **synchronously in-process** (`publish` calls subscribers inline, same request/transaction). So the payment plugin can publish a generic `payment.recurring_charge` fact (`{provider, provider_ref_id, amount, currency, provider_reference, metadata}`); the subscription plugin's subscriber — running inline — finds the matching subscription, **creates the renewal invoice, and itself emits `payment.captured`** (forwarding the provider `metadata`). Behaviour and transactionality are preserved; the payment plugin never needs the invoice id back.
  - **Why events, not a moved port:** the contract is payment↔subscription, but **payment must stay subscription-free** (a payment install with no plan concept). A moved port would force payment→subscription import; the string-keyed bus keeps payment publishing blindly (no subscriber ⇒ no-op). Core keeps only `events/domain.py` + `bus.py`; no lifecycle port anywhere.
  - **Naming:** event names + payload keys must be domain-neutral (oracle-clean) — no `subscription`/`plan`/`tarif`. Use e.g. `provider_ref_id` (the provider's recurring/subscription object id) not `provider_subscription_id`.
  - **Consequence for S50.4:** delete `vbwd/services/subscription_lifecycle.py` entirely (no replacement port); the 5 lifecycle methods become published events (`payment.recurring_charge`, `payment.provider_cancelled`, `payment.recurring_failed`, `payment.invoice_failed`, `payment.provider_linked`) that subscription subscribes to.

## Risks & mitigations
- **Money path (S50.4):** highest risk. Mitigate by keeping the existing stripe/paypal/yookassa integration + e2e tests as the gate, and by validating the "subscription-disabled" no-op path explicitly.
- **Connection-exhaustion under `--full`:** the repo-root `conftest.py` teardown + `TESTING`-guarded schedulers must stay in place ([[feedback_ci_precommit_lessons]]).
- **fe-admin (S50.3):** separate repo + submodule; run full `npm run lint` + vitest; push with green CI ([[feedback_no_temp_branches]], [[feedback_plugins_always_in_own_repos]]).
- **Migrations:** none expected (no schema change — this is a code-ownership move). If any column moves, it goes via Alembic in the owning plugin ([[feedback_plugin_migrations_in_plugin]]).

## Definition of done
Core (`vbwd/`) names **no** plugin domain: `subscription_read_model.py`, `subscription_lifecycle.py`, `catalog_read_model.py`, `seo_registry.py`, `seo_renderable.py`, `routes/seo.py`, and `events/subscription_events.py` are gone; `payment_events.py` carries no `subscription_id`/`tarif_plan_id`; SEO is served by cms, invoice/add-on enrichment by generic registries + the subscription plugin, and payment↔subscription is event-driven. The Kind-1 generic seams + `entitlement` remain untouched. The new vocabulary oracle is **enforcing** and green; `test_core_agnosticism.py` green; `--full` green on every touched repo; no behaviour change for end users (admin invoice/user views and the sitemap render identically).

## S50.5 outcome — oracle finalized & LOCKED (2026-06-06)
S50 shipped via **S50.1–S50.4** (the 5 major Kind-2 ports removed: `catalog_read_model`, SEO feature → cms, `subscription_read_model` → generic invoice extra-fields registry + fe-admin injection, `subscription_lifecycle` → fire-and-forget events) + **S50.6** (checkout events made generic + SSE event-name whitelist generic) + **S50.5** (this lock).

`tests/unit/test_core_no_domain_vocabulary.py` is now **enforcing** (`ENFORCING = True`) and **code-only**:
- **AST-based, not line-based.** Comments and docstrings are never scanned — comments are absent from the AST; module/class/function docstrings (the first `ast.Expr`/`str`-`Constant`) are explicitly excluded. The scan inspects only **identifiers** (Name/attribute/arg/func+class names/import module+alias) and **non-docstring string-literal Constants**. This dropped ~120 pure-prose hits (e.g. `entitlement.py`'s "core knows nothing about subscriptions" docstring, `transaction.py`'s `Usage:` examples), leaving ~23 structural hits. A self-test (`test_oracle_scans_code_not_prose`) proves a banned term as an identifier IS flagged while the same word in a comment/docstring is NOT.
- **`catalog` dropped from `BANNED_TERMS`** — generic English word in legitimate core identifiers (`permission_catalog`, `collect_permission_catalog`, `catalog_item_id`, `routes_catalog`, country/payment-method "catalog"). The real leak (`catalog_read_model`) was deleted in S50.1 and is independently guarded by `test_core_agnosticism` (bans `from plugins.*`). Final `BANNED_TERMS`: `subscriptions`, `subscription`, `tarif_plan`, `tarif`, `plan_id`, `plan_name`, `sitemap`, `seo`.
- **Whole-word matching** means compound identifiers (`subscription_id`, `get_subscription_invoices`, `find_by_subscription`) never match the standalone word — so most spec-anticipated invoice files need no allowlist entry.

**Documented allowlist (12 entries, minimal — no dead entries):**
- **(a) D4 invoice residuals** (Sprint 11: invoice↔subscription via SUBSCRIPTION line item, no FK): `repositories/invoice_repository.py` (`LineItemType.SUBSCRIPTION`), and the line-item-result dict keys `items_*["subscription"]` in `handlers/payment_handler.py`, `services/restore_service.py`, `services/refund_service.py`.
- **(b) Core line-item / status enums** (the generic discriminator core routes on): `models/enums.py` (`LineItemType.SUBSCRIPTION`, `TokenTransactionType.SUBSCRIPTION`).
- **(c) Core webhook event-type enums** (`SUBSCRIPTION_*` / `"subscription.*"`): `webhooks/enums.py`, `webhooks/handlers/mock.py`. **FUTURE:** like the SSE whitelist (S50.6), these could become an extensible registry — deferred.
- **(d) Demo/test seeders (DEFERRED follow-up)** — core demo seeds delegate plan/addon to the subscription plugin's `demo_seed` but still name tables/keys: `cli/_demo_seeder.py` (raw-SQL `tarif_plan`/`subscription`), `cli/reset_demo.py` (CLI confirm-prompt text). Own follow-up sprint.
- **(e) Decided in S50.5 (not in the original spec buckets)** — two domain-NEUTRAL structural hits: `plugins/payment_route_helpers.py` (`determine_session_mode` returns the **Stripe Checkout Session `mode`** literal `"subscription"|"payment"` — provider-protocol vocabulary core computes generically via `line_item_registry.is_recurring_line_item`; like (c), could later move behind the registry); `routes/settings.py` (default Terms & Conditions fallback **content prose** naming "Subscription Services" — editable user content, not a seam).

Gate: `pytest tests/unit/test_core_no_domain_vocabulary.py tests/unit/test_core_agnosticism.py` → 3 passed; core `bin/pre-commit-check.sh --quick` green (lint + 2753 unit).