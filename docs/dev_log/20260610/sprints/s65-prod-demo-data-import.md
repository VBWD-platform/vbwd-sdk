# S65 — Prod demo-data import + checkout proof (hotel & doctor & shop)

**Depends on:** S61–S64 implemented **and deployed to the demo instances** · **Type:** data + ops + test
**Engineering requirements:** TDD-first where code is touched; the deliverable proof is a green
Playwright run + HTML report. `bin/pre-commit-check.sh` green on any plugin touched. See overview +
`_engineering-requirements.md`.

## Goal
Using the unified import/export (S61–S64), author **per-vertical JSON import envelopes**, deploy the
updated plugins to the prod demo instances, **import the demo catalogues through the unified Import/
Export UI**, configure discounts/coupons + Stripe, and produce an **HTML walkthrough report with a
screenshot at every step** proving checkout works **with a coupon, without a coupon, paid by Stripe
(test card), and paid by tokens**.

## Phase 0 — deploy S61–S64
- Rebuild + deploy the backend image carrying the four plugins' new exchangers to the demo
  instances (CI build → ghcr → manual `docker compose pull api && up -d api` per instance, since the
  CI VPS-deploy step is blocked — see `feedback_deploy_github_only`). Verify each new entity_key
  appears in `GET /api/v1/admin/data-exchange/manifest` on each instance.

## Phase 1 — author the import envelopes (artifacts, committed under docs/marketing/cms-imports/<vertical>/booking/)
Per vertical, JSON envelopes in the unified format (one file per entity_key):

**Hotel** (`booking_categories` + `booking_resources`) — replaces the current generic demo
(removes Dr. Smith/Johnson/Yoga etc.):
- 5 categories (one per hotel): e.g. `grand-marina`, `alpine-lodge`, `seaside-resort`,
  `city-center`, `lakeview-retreat` (names TBD with user; demo-appropriate).
- Per hotel (`category_slugs` → that hotel), resources:
  - Rooms (price `per_night`): Standard Room (capacity 12), Deluxe Room Sea View (3),
    Superior Deluxe (8), Family Room (4).
  - SPA/facilities (`per_slot`): SPA Full Day, SPA 3 Hours, Massage Thai, Massage Sport,
    Steam Sauna Event Aufguß, Meditation, Aquapark.
  - Business (`per_day`/`per_slot`): Conference Room A (capacity 300), Conference Room B
    (capacity 4 — "4 rooms × 50 guests"), Catering Service.
  - Each with a standard `availability` schedule. **Per-hotel** facilities (user-confirmed) → ~14
    resources × 5 = ~70 resources, slugs prefixed by hotel (`grand-marina-standard-room`, …).

**Doctor** (`booking_categories` + `booking_resources`) — aggregator model:
- 12 categories = nosologies: cardiology, urology, neurology, dermatology, orthopedics,
  gastroenterology, ophthalmology, endocrinology, pulmonology, gynecology, pediatrics, oncology.
- Resources = **clinics** (not doctors): each nosology has 3–15 clinics (`category_slugs` → its
  nosology), `per_slot` consultation pricing + availability. Remove the current generic doctor
  resources first.

**Shop** (if in scope for a demo storefront): `shop_product_categories` + `shop_products` —
a small demo catalogue (categories + a handful of products with variants).

Subscription/GHRM plans already exist on the instances; export from a reference instance only if a
target is missing plans.

## Phase 2 — import via the unified UI
- Log in as the temp super-admin (`claude0610.admin@vbwd.cc`) on each instance; open the core
  Import/Export view; upload each envelope **in dependency order** (categories → resources;
  plan categories → plans → addons → ghrm packages). Verify created/updated counts + zero errors.
- Verify the catalogue: hotel `/booking` lists only hotel resources grouped by the 5 hotels;
  doctor `/booking` lists clinics by nosology; `/booking-form/<resource>` works.

## Phase 3 — discounts & coupons
- Via the discount plugin (investigate its model/admin API in the sprint): create on hotel (at
  least) a **percentage coupon** (e.g. `WELCOME10` = 10%) and a **fixed discount** (e.g. a seasonal
  10 EUR off), active, with a known code for the test. Document the exact codes used by the report.

## Phase 4 — Stripe (test mode)
- Copy the **local config's Stripe keys** (publishable + secret; confirmed TEST keys) into each
  demo instance's payment config (the same mechanism the local stack uses — locate in the local
  `.env`/payment config during the sprint). Enable the Stripe payment method on the instance.
- Verify token-payment is enabled and a test user holds a token balance (top up via admin if needed)
  for the token-checkout path.

## Phase 5 — Playwright proof + HTML walkthrough report
A Playwright spec (committed under `vbwd-fe-admin/vue/tests/e2e/` or a dedicated e2e folder),
screenshotting **every step**, producing a single self-contained HTML report. Four checkout journeys
on the prod demo site (Stripe **test** mode → no real charges):
1. **Booking checkout, no coupon, Stripe**: catalogue → resource → `/booking-form` → checkout →
   Stripe Elements test card `4242 4242 4242 4242` → confirmation.
2. **Booking checkout, with coupon, Stripe**: same, applying the `WELCOME10` coupon → assert the
   discounted total → pay → confirmation.
3. **Checkout paid by tokens** (token-payment): a token-priced item / token balance → pay with
   tokens → confirmation (no Stripe).
4. **Without coupon vs with coupon** total comparison asserted in the report.
- Assertions: discounted total correct; Stripe payment succeeds (test); token balance debited;
  invoice + booking/subscription created; `/checkout/confirmation` renders the order.
- Output: `docs/dev_log/<date>/walkthrough/checkout-proof.html` (base64 screenshots), like the prior
  admin walkthrough. Notes: Stripe Elements is in an iframe — drive it via Playwright frame locators;
  use Stripe **test** keys only.

## Acceptance
- Manifests on all demo instances list the new catalog entities; envelopes import with zero errors.
- Hotel = 5 hotels with rooms/facilities/business, no doctors; doctor = 12 nosologies × clinics.
- Discounts/coupons created; Stripe (test) + tokens both complete checkout.
- The HTML report shows all four journeys green with per-step screenshots.

## Risks / notes
- Backend deploy to prod is the blocked-CI manual path — schedule it carefully (rebuild api image,
  pull+restart per instance, run migrations if S62/S64 added any e.g. an Addon `slug`).
- Stripe Elements automation is the trickiest test bit (iframe + test card). Token-payment requires
  a funded test user. Discounts: confirm the discount plugin's coupon model + apply-at-checkout
  hook before writing the test. Keep all keys TEST; never commit secrets — read from instance config.
