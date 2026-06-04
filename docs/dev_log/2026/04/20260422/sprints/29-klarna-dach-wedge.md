# Sprint 29 — Klarna + SEPA DD ("Klarna without Shopify", DACH wedge)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** [`payment-plugins-market.md §6.1`](../../../dev_docs/market-research/payment-plugins-market.md)
**Repos touched:**
- `vbwd-plugin-klarna` (NEW — backend plugin: Klarna Payments API v3 adapter, widget endpoints, webhook handler)
- `vbwd-fe-user-plugin-klarna` (NEW — checkout widget mount + PDP on-site messaging)
- `vbwd-fe-admin-plugin-klarna` (NEW — merchant config UI: API keys, region selector, test mode toggle)
- `vbwd-plugin-sepa-dd` (NEW — backend plugin: SEPA Direct Debit mandate + collection via GoCardless or native SEPA XML file export)
- `vbwd-fe-user-plugin-sepa-dd` (NEW — IBAN entry, mandate signing UI, recurring consent)
- `vbwd-fe-admin-plugin-sepa-dd` (NEW — mandate management, retry queue, batch collection)
- `vbwd-demo-instances` (configure a new `dach-shop` instance showcasing the bundle)

**No changes to `vbwd-backend` core, `vbwd-fe-core`, `vbwd-fe-user`, `vbwd-fe-admin`** — per `feedback_plugins_always_in_own_repos.md`, all plugin code stays in standalone repos.

## Goal

Ship a turnkey **DACH payment bundle** so a German, Austrian, or Swiss
merchant can install VBWD, drop in Klarna + SEPA Direct Debit, and sell
physical goods online the same day — without Shopify or Shopware in the
stack. The wedge is anchored by three claims we must be able to demonstrate
on a live demo at the end of the sprint:

1. **Klarna BNPL** (Pay later in 30 days, Pay in 3 / in 4 instalments,
   Pay now via Klarno direct-debit) fully works on a DACH test merchant
   account, including the Klarna widget on checkout and on-site PDP
   messaging ("ab 12,50 € / Monat mit Klarna").
2. **SEPA Direct Debit** is live for recurring subscriptions: user enters
   IBAN on checkout, signs the SEPA mandate electronically, and the
   mandate is persisted and presented to the admin for batch collection.
3. A **demo instance** (`dach-shop.demo.vbwd.io`) ships with the bundle
   pre-enabled and can be handed to a prospect without further setup.

**Commercial targets tied to this sprint:** at least one pilot merchant in
DACH (EUR 300K–5M GMV fashion/home-goods SMB) signs an LOI by
2026-05-15. Outreach channel: German Shopware + Adobe Commerce partner
agencies (distribution handled outside this sprint, but all demo assets
produced here).

## Core engineering requirements (binding for every deliverable)

These are non-negotiable and mirror Sprint 28's framework
([`../../20260403/sprints/28-user-booking-dashboard.md`](../../20260403/sprints/28-user-booking-dashboard.md)).
A deliverable is not "done" until it satisfies every item below for the
code it touches.

### 1. TDD-first
- Every adapter method, service, and webhook handler has its pytest
  written first, watched fail, then implementation.
- Concrete checkpoints:
  - `KlarnaAdapter.create_session(order)` — happy path + missing billing
    address 400 + unsupported region 422 specs authored **before** the
    method body.
  - `KlarnaWebhookHandler.handle("order.captured")` — idempotency spec
    (same event id twice ⇒ one state transition) authored **before** the
    handler.
  - `SepaMandateService.create_mandate(user, iban)` — IBAN-checksum
    validation spec, BIC-derivation spec, duplicate-mandate spec authored
    **before** the method body.
  - `SepaBatchService.export_pain008_xml(mandates, run_date)` — snapshot
    test of generated XML (ISO 20022 `pain.008.001.02`) authored
    **before** the renderer.
- Frontend: Vitest spec beside every new store/component; Playwright E2E
  for the full checkout flow (Klarna hosted-payment-page callback + SEPA
  mandate UI).

### 2. DevOps-first
- Klarna sandbox credentials are injected via env, never committed.
  `vbwd-plugin-klarna/README.md` documents the 4 required env vars
  (`KLARNA_API_USERNAME`, `KLARNA_API_PASSWORD`, `KLARNA_REGION`,
  `KLARNA_WEBHOOK_SECRET`).
- SEPA plugin Alembic migration lives in
  `vbwd-plugin-sepa-dd/alembic/versions/<timestamp>_create_sepa_tables.py`.
  Never raw SQL (see `feedback_migrations_only.md`).
- CI matrix on all 6 new repos must stay green before merge. `bash -n`
  on any edited pre-commit-check.sh (see `feedback_ci_precommit_lessons.md`).
- Dockerfile for any plugin that needs additional system libs (none
  expected for Klarna; SEPA export may need `libxmlsec1` if we go the
  signed-XML route — decide in Q1).
- Demo instance config goes to `vbwd-demo-instances/instances/local/dach-shop/`
  first (localhost-only), then `instances/dach-shop/` for prod deploy
  (see `feedback_never_mix_local_and_prod_compose.md`).

### 3. SOLID
- **SRP:** `KlarnaAdapter` speaks Klarna API only — knows nothing about
  VBWD orders or invoices. `KlarnaPaymentService` is the VBWD-side
  service that maps between Order/Invoice domain and Klarna DTOs.
- **OCP:** New regions (e.g. Netherlands, Sweden) added by extending the
  region-config table, not by editing `KlarnaAdapter`.
- **LSP:** `KlarnaPaymentService` implements `IPaymentAdapter` contract
  (same as Stripe, PayPal, YooKassa). Swapping it in must not weaken
  postconditions of the generic payment flow.
- **ISP:** The public VBWD payment interface stays narrow. Klarna-specific
  metadata (e.g. `authorization_token`) is handled internally — not
  leaked into the generic `PaymentResult` DTO.
- **DP:** All collaborators injected via constructor DI.

### 4. DRY
- One HTTP client factory shared between Klarna and future payment
  adapters in the same repo pattern (`plugin/adapter/http_client.py`).
  If a third adapter needs it, promote to `vbwd-sdk-py` (out of scope).
- IBAN validation is written once in `vbwd-plugin-sepa-dd/sepa/utils/iban.py`
  — no duplication into fe-admin/fe-user (frontends call the backend
  `/api/v1/sepa-dd/validate-iban` endpoint or use a thin client-side
  checksum via `ibantools` npm — one or the other, not both).
- Klarna and SEPA share zero code. They are independent plugins with
  independent lifecycles — do **not** introduce a "dach-bundle" meta-plugin.

### 5. Dependency injection
- Backend services receive collaborators through constructors:
  `KlarnaPaymentService(klarna_adapter, order_repo, invoice_repo, event_dispatcher)`.
- Webhook handler receives its adapter + dispatcher via DI; no
  module-level singletons.
- Frontend Pinia stores stay singleton, but any composable that calls an
  API takes the `sdk` / `api` client as an argument (for testability).

### 6. Clean Code
- Full, pronounceable names per `feedback_variable_naming.md`:
  `createKlarnaSession`, not `createKS`. `sepaDirectDebitMandate`, not
  `sddm`.
- Functions < 30 lines. No flag arguments on public methods.
- Zero "what" comments — only "why" comments for regulatory rules
  (e.g., "SEPA Core mandate requires 14 calendar days pre-notification —
  do not shrink this window").
- `black` / `isort` / `flake8` on backend; `eslint` + `prettier` on
  frontend; all gated in pre-commit.

### 7. No over-engineering
- No generic "BNPL adapter framework" — Klarna only. Afterpay, Affirm,
  Clearpay are separate plugins if/when we need them.
- No "multi-PSP routing layer" — VBWD core already picks the adapter per
  order based on configured payment methods.
- No retries, exponential backoff, or circuit breaker beyond what the
  Klarna / SEPA libraries already provide. A single retry on 5xx with a
  3-second wait is enough for v1.
- No admin analytics dashboard for Klarna / SEPA volumes this sprint.
  Ship basic transaction list; wait for a real merchant to ask for more.

### 8. Drop deprecated
- **Delete, don't comment out.** Any demo-fixture payment method in
  `vbwd-demo-instances/instances/local/dach-shop/` that was used for
  scaffolding gets removed before the PR lands.
- No `// TODO: implement later` markers. If it isn't in this sprint, it
  isn't in the diff.
- Old environment example files for Klarna (if any pre-existing stub)
  are deleted, not kept alongside the real one.

### Gate

A deliverable is accepted when:
1. Its spec(s) were authored first and are now green.
2. `make pre-commit-quick` (backend) and `npm run lint && npm run test`
   (frontend) pass on every touched repo.
3. Demo instance boots cleanly with the bundle enabled: checkout with
   Klarna sandbox + SEPA mandate both complete end-to-end.
4. No item above is violated in the diff.

## Current state (baseline)

- **Core**: `vbwd-backend` already has `IPaymentAdapter` interface
  (Stripe, PayPal, YooKassa implement it). `vbwd-fe-user/vue/src/views/Checkout.vue`
  dispatches to the plugin-provided checkout widget via the payment
  plugin registry. No Klarna, no SEPA DD.
- **Infrastructure**: VBWD already ships invoice + order + user domain
  + webhook dispatcher. No schema changes to core.
- **Demo instances**: `main`, `shop`, `hotel`, `doctor`, `ghrm` exist.
  No `dach-shop` yet.

## Deliverables

### D1 — `vbwd-plugin-klarna` backend plugin

- Folder structure per `MEMORY.md` plugin convention:
  ```
  vbwd-plugin-klarna/
    klarna/__init__.py          # KlarnaPlugin(BasePlugin)
    klarna/klarna/               # plugin-id source dir
      adapters/klarna_adapter.py # HTTP client → Klarna Payments API v3
      services/klarna_service.py # maps VBWD Order/Invoice ↔ Klarna DTOs
      routes.py                  # Blueprint — create-session, authorize, capture, webhook
      models/klarna_session.py   # persisted session id + state for reconciliation
      webhooks/handler.py        # idempotent handler for order.captured, order.refunded
    tests/unit/, tests/integration/
    alembic/versions/<ts>_create_klarna_tables.py
    populate_db.py               # seeds one test Klarna-enabled product + order
    plugins.json patch + config.json patch
  ```
- Routes (all under `/api/v1/klarna/`):
  - `POST /sessions` — create Klarna session for an order; returns
    `{ client_token, session_id }`.
  - `POST /sessions/:id/authorize` — on-client-side callback to finalize
    with `authorization_token`; server calls Klarna `POST /payments/orders`
    to create the order on Klarna's side. Persists state.
  - `POST /webhooks` — Klarna webhook receiver. Verifies signature,
    dispatches internal events (`payment.klarna.captured`, `.refunded`).
- Implements `IPaymentAdapter` so VBWD's invoice flow picks it up via
  config.
- Unit tests: adapter request/response, mapping correctness, webhook
  signature verification, idempotency.
- Integration tests: full create-session → authorize → capture round
  trip against Klarna sandbox (hit gated by `KLARNA_SANDBOX=1` env —
  skipped in default CI).

### D2 — `vbwd-fe-user-plugin-klarna`

- Plugin structure per `feedback_plugins_always_in_own_repos.md` and
  `fe-user Plugin Export Convention` (named exports).
- New files:
  - `klarna/index.ts` — `export const klarnaPlugin: IPlugin` with
    `install(sdk)` registering: Klarna widget component for checkout,
    on-site-messaging component (installment preview on PDP), i18n keys.
  - `klarna/components/KlarnaCheckoutWidget.vue` — mounts Klarna JS SDK,
    listens for the authorization event, POSTs token to
    `/api/v1/klarna/sessions/:id/authorize`.
  - `klarna/components/KlarnaOnSiteMessaging.vue` — small widget that
    renders "ab 12,50 € / Monat mit Klarna" via Klarna's on-site-messaging
    library. Usable anywhere fe-user has a product-price context.
  - `klarna/stores/klarna.ts` — Pinia store: session state, errors,
    country/region selector (DE / AT / CH / NL as launch set).
- i18n: de, en, fr keys at minimum (German is primary; English for
  demos; French for CH-FR merchants).
- Playwright E2E: checkout flow that selects Klarna Pay-later, finishes
  Klarna sandbox redirect, lands back on `/checkout/success`.

### D3 — `vbwd-fe-admin-plugin-klarna`

- Admin-side config view: Klarna API username / password (write-only,
  masked on read), region selector, test-mode toggle, webhook URL (read-
  only, derived).
- Transaction list view: lists recent Klarna sessions with state, order
  link, amount, Klarna order-id.
- Register navigation entry under Payments → Klarna.
- Uses existing admin patterns (Pinia store + API client). No new core
  views.

### D4 — `vbwd-plugin-sepa-dd` backend plugin

- Folder structure mirrors D1.
- Domain:
  - `SepaMandate` model — mandate id, user id, IBAN (stored encrypted at
    rest via existing `vbwd-backend` crypto helper), BIC, creditor id,
    mandate reference, signature timestamp, IP, status
    (`pending_signature`, `active`, `revoked`, `expired`).
  - `SepaCollection` model — scheduled collection per invoice; state
    (`pending`, `submitted`, `succeeded`, `failed`, `returned`).
- Services:
  - `SepaMandateService` — create / sign / revoke mandates; generate
    mandate PDF (reuses core `PdfService` from Sprint 28).
  - `SepaBatchService` — group active mandates' upcoming collections into
    a batch, render ISO 20022 `pain.008.001.02` XML, export file to
    storage and/or push to bank SFTP (configurable; file-export is the
    default for v1).
- Routes (all under `/api/v1/sepa-dd/`):
  - `POST /mandates` — create a new mandate (user-owned, auth required).
  - `GET /mandates/:id/pdf` — downloads signed mandate PDF.
  - `POST /mandates/:id/revoke` — user-initiated revocation.
  - `GET /admin/mandates` — admin list.
  - `POST /admin/batches` — admin triggers a batch run for a date window;
    returns generated `pain.008` XML.
  - `GET /admin/batches/:id/xml` — re-download generated XML.
- Implements `IPaymentAdapter` for subscription charges — when an
  invoice becomes due and the merchant's configured payment method is
  SEPA DD, it enqueues a `SepaCollection` instead of attempting a card
  charge.
- Alembic migration for both tables.
- Unit tests: IBAN checksum, BIC derivation, mandate lifecycle, XML
  snapshot.

### D5 — `vbwd-fe-user-plugin-sepa-dd`

- Checkout widget: IBAN input (client-side format check, server-side
  validation), mandate consent text (legally required wording — stored
  in i18n under `sepa.mandateText.de` / `.en`), "Sign mandate" button.
- On submit, POSTs IBAN to `/api/v1/sepa-dd/mandates`; on success,
  displays mandate id + PDF download link + "Finish order" button.
- Subscription recurring flow: existing invoice flow picks up SEPA as
  payment method with no extra UI from the plugin.

### D6 — `vbwd-fe-admin-plugin-sepa-dd`

- Mandates list with state filter.
- Batches list + "Run batch" action.
- Returns (Rückläufer) handling UI — admin marks a collection as
  returned with a reason code; the collection becomes `failed`, invoice
  is flagged for manual retry.

### D7 — DACH demo instance

- `vbwd-demo-instances/instances/local/dach-shop/docker-compose.yaml`
  — localhost-only stack with backend + fe-user + fe-admin + Postgres
  + Redis, plus all 6 new plugins activated.
- `vbwd-demo-instances/instances/local/dach-shop/populate_db.sh` —
  seeds: 1 admin, 1 customer, 3 products priced in EUR, 1 subscription
  plan billed monthly via SEPA DD, 1 active Klarna test-merchant config.
- `vbwd-demo-instances/instances/dach-shop/docker-compose.yml` — prod
  overlay (domain: `dach-shop.demo.vbwd.io`). Only added once the local
  variant is stable.
- README walkthrough: "install, run, buy a jacket with Klarna, subscribe
  to monthly box with SEPA, admin generates SEPA batch".

### D8 — Marketing assets

- Landing page copy on `vbwd.io` marketing site (if marketing CMS is
  running, otherwise a markdown draft handed to marketing): "Klarna for
  your own shop — without Shopify tax."
- One-page PDF flyer (German + English) built from same copy via the
  core `PdfService` template — reuses the invoice PDF template
  infrastructure from Sprint 28, so no new PDF engine needed.
- Out of scope: ads, outbound email campaigns, partner contracts (all
  handled by the commercial team after sprint close).

## Tests

- **Backend (pytest)**: ≥ 35 unit tests across the two plugins; ≥ 8
  integration tests for Klarna sandbox; IBAN / BIC / PAIN008 snapshots.
- **Frontend (Vitest)**: ≥ 20 specs across 4 frontend plugins.
- **E2E (Playwright)**: one full checkout journey per flow (Klarna
  Pay-in-4 happy path; SEPA mandate signing happy path; SEPA recurring
  renewal via cron).
- **Contract tests** (optional stretch): Klarna sandbox contract test
  using their published OpenAPI spec — gated by sandbox env, not part
  of default CI.

## Out-of-scope (follow-ups)

- **S29.1** — Klarna refunds & chargebacks admin UI. Webhook handler
  records them; UI ships next sprint.
- **S29.2** — BACS Direct Debit (UK) — mirrored plugin, own sprint.
- **S29.3** — Bancontact / iDEAL / SOFORT via Klarna OR Mollie — decide
  after pilot-merchant feedback.
- **S29.4** — Klarna Sign-In ("Buy now, identified with Klarna")
  — interesting but not needed for first pilot.

## Risks

- **PCI scope**: Neither plugin touches card PANs (Klarna hosts its own
  payment widget; SEPA is bank-to-bank). VBWD stays SAQ-A eligible.
  Document this in each plugin README.
- **SEPA creditor identifier**: the merchant must register with their
  bank for a Creditor ID before collecting. Document the setup steps in
  the SEPA plugin README; config won't accept collections until a
  Creditor ID is set.
- **Klarna regional variance**: approval rates and available methods
  differ per country. Hardcode the launch-set (DE/AT/CH/NL) and let the
  merchant pick one; reject orders from other countries with a clear
  error rather than silently failing.
- **Mandate PDF regulatory wording**: the SEPA mandate text has legal
  requirements. Use the official European Payments Council template as
  the source; do not hand-write wording.

## Open questions

- [ ] **Q1 — SEPA delivery.** Native `pain.008` XML file export only for
  v1, or ship a GoCardless adapter too? (File-only keeps scope tight; GC
  cuts merchant onboarding friction.) Recommended: **file-only**, ship
  GC as S29.5 if merchant asks.
- [ ] **Q2 — Mandate signing strategy.** Pure web-based "tick box + IP
  record" (sufficient for SEPA Core under ZKA guidance), or add
  e-signature integration (DocuSign / SignRequest)? Recommended:
  **tick-box + IP record**; upgrade only when a pilot merchant asks.
- [ ] **Q3 — Klarna regions for launch.** DE + AT + CH only, or DE +
  AT + CH + NL? NL has iDEAL dominance, so Klarna share is lower there —
  defer? Recommended: **DE + AT + CH for v1**, NL in S29.3.
- [ ] **Q4 — Merge shared payment-plugin scaffolding?** Both plugins
  need IPaymentAdapter wiring + webhook boilerplate. Extract into
  `vbwd-plugin-payment-sdk-py`? Recommended: **no for v1** — two copies
  is fine per DRY §7; revisit on 3rd adapter.

## Effort estimate

- Klarna backend adapter + routes + tests: **2 days**
- Klarna fe-user widget + on-site messaging + e2e: **1.5 days**
- Klarna fe-admin config + transaction list: **1 day**
- SEPA backend (models, services, pain.008 renderer, tests): **2.5 days**
- SEPA fe-user mandate UI: **1 day**
- SEPA fe-admin mandates + batches + returns: **1.5 days**
- DACH demo instance + populate: **0.5 day**
- Marketing assets: **0.5 day**

**Total: ~10.5 person-days.** Klarna and SEPA tracks can run in parallel
(different sub-teams) — calendar time ≈ 6 working days with two devs.
