# Sprint 53 — bot commerce storefront (`subscription` over the messenger bridge)

**Status:** PLANNED — 2026-06-06. **Carved out of [S45](s45-bot-base-bridge.md)** (the D8 decision, locked there); depends on the S45 bridge ([45.0 bot-base](s45-0-bot-base-foundation.md)) being green.
**Area:** `subscription` backend plugin (new bot-storefront consumer + `subscription_bot_checkout_draft` model/migration + public draft-resolution endpoint) **+** a small `fe-user` change (`PublicCheckoutView` accepts `?draft=<token>`). No core change; the `subscription` plugin owns all storefront logic. Token bundles + balance are read from **core** (plugin→core read is allowed).
**Depends on (S45, must be green first):** the provider-neutral bridge seams — `BotCommandProvider`/`BotCommand`, the `BotInbound`/`BotReply`/`BotChoice` DTOs (D6), the abstract-choice / tapped-`action_data` dispatch path (D7), `CommandRegistry` collection from enabled plugins (D1), `LinkService`/identity linking (D3), and the exported `MessengerService` (Seam A). This sprint adds **no** new bridge capability — it is purely a new consumer on the existing seam.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). Full, readable variable names — no cryptic abbreviations ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin subscription --full` green = "done" on the backend; `fe-user` lint + unit + e2e green for the hydration change. Tables follow the [S43](s43-db-table-naming-normalization.md) convention `subscription_<model>`. Plugin migrations live in the plugin, registered in `alembic.ini` ([[feedback_plugin_migrations_in_plugin]]); revision ids ≤ 32 chars. Baseline `config.json` + `admin-config.json` with at least `debug_mode` ([[feedback_plugin_baseline_config_files]]). Test/demo data only through services, never raw SQL ([[feedback_no_direct_db_for_test_data]]).

## Goal

A **bot commerce storefront**: a Telegram (and, via D6, any-messenger) user can browse tarif plans, add-ons and token bundles, accumulate a selection, and hand off to the **existing unregistered browser checkout** to pay — with **no new checkout logic** and **no charge created by the bot**.

Because it is written on S45's provider-neutral DTOs (D6), the same storefront lights up over **any** future messenger provider (meinchat, WhatsApp, Slack, …) with zero consumer change.

## Consumer: `subscription` implements `BotCommandProvider`

The `subscription` plugin implements the S45 seam (`bot_namespace="subscription"`). It reuses existing **public** catalogs and the **existing checkout** — it reimplements nothing:
- tarif plans + add-ons → subscription plugin's own services (`subscription_tarif_plan`, `subscription_addon`).
- token bundles → **core** public catalog `GET /api/v1/token-bundles/` (token bundles + balance are core; plugin→core read is allowed).
- token balance → **core** `TokenBalanceRepository.find_by_user_id(user_id).balance`.

New config (additive to `subscription` `DEFAULT_CONFIG`): `bot_storefront_enabled` (bool), `checkout_link_base_url` (the public fe-user origin), `checkout_draft_ttl_seconds`. When `bot_storefront_enabled` is false or the bridge is absent, `get_bot_commands()` is simply never collected (D1) — web behaviour is unchanged.

**Commands** (all selection via abstract `BotReply.choices`, D7):
- **`/tarifs`** — *anonymous.* Lists active tarif plans as `choices`; a tap records the chosen plan into the chat's **checkout draft** (single plan, replaces any prior). Claims the conversation owner = `subscription`.
- **`/add-ons`** — *anonymous.* Lists add-ons as toggle `choices`; taps add/remove add-ons in the draft.
- **`/tokens`** — the token-bundle **catalog** is *anonymous* (`choices` to add a bundle to the draft); the **balance** line ("You have N tokens") shows **only when the chat is linked** (D3) — reads the core balance. Unlinked → catalog only + a one-line "link your account to see your balance" hint (no billing, no identity mutation — Security §4).
- **`/checkout`** — *anonymous.* Finalizes the draft → mints a **one-time, TTL'd checkout-draft token** → replies with a single link `{checkout_link_base_url}/checkout?draft=<token>` that opens the **existing unregistered `PublicCheckoutView`** with the cart pre-seeded from the draft's line items. Payment completes in the browser (login/register prompt as today). The bot never collects payment and never debits anything.

## Checkout draft (D8) — the bridge from bot to browser

The per-chat selection can't ride a browser localStorage cart across the boundary, so it lives server-side as a draft of **generic line items** (`{item_type ∈ {SUBSCRIPTION, ADD_ON, TOKEN_BUNDLE}, item_id, quantity}` — the core `LineItemType` vocabulary), owned by the `subscription` plugin (the checkout owner).

New model **`subscription_bot_checkout_draft`** (S43 naming, provider-neutral): `chat_ref`, `provider_id`, `line_items` (JSON), `token` (nullable until `/checkout`), `expires_at`. On `/checkout` we set a random one-time `token` + TTL and return the link.

A **public** (no-auth) endpoint `GET /api/v1/subscription/public/checkout-draft/<token>` resolves the draft → line items with names/prices **recomputed from the catalogs** (never trust client prices) → fe-user seeds the fe-core cart ([[project_checkout_cart_backed_selections]]) and renders through the **existing** `checkoutSourceRegistry`. Token is single-use + expiring; the URL carries no identity and no price — only an opaque token.

## fe-user change (small)

`PublicCheckoutView` accepts `?draft=<token>`: on mount it fetches the draft, hydrates the fe-core cart from its line items, then proceeds exactly as today's cart-backed public checkout. **No new checkout logic** — only cart hydration from a draft. (This is the S45 D3 "fe-user follow-up" note, realized here alongside the storefront it serves.)

## Security (CRITICAL)

1. **Checkout draft token** — the `?draft=<token>` is a **random, single-use, TTL'd** opaque token; it carries **no identity and no prices**. The public draft-resolution endpoint recomputes names/prices/totals from the live catalogs server-side (never trusts amounts persisted from the bot side), returns only catalog item ids + quantities, and creates **no** invoice/subscription/charge — payment still happens through the normal authenticated/registering checkout in the browser. Expired or already-redeemed tokens 404.
2. **Anonymous by default** — `/tarifs`/`/add-ons`/`/tokens` (catalog) and `/checkout` need no vbwd identity; only the `/tokens` **balance line** requires a linked chat (D3). Never bill or mutate a vbwd user from an unlinked messenger id.
3. **No price trust** — amounts are always recomputed server-side from the catalogs; the draft persists only `{item_type, item_id, quantity}`.

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock repos):
  - `/tarifs`/`/add-ons`/`/tokens` build `BotReply.choices` from the catalogs; a tapped `action_data` mutates the checkout draft (plan **replaces**; add-on/bundle **toggle**).
  - `/tokens` shows the balance line only when the chat is linked; catalog-only + hint when unlinked (no billing, no identity mutation).
  - `/checkout` mints a one-time TTL token and returns `{checkout_link_base_url}/checkout?draft=<token>`.
  - **Provider-neutrality (reuses S45 D6/D7):** a fake non-Telegram provider drives the same storefront handlers unchanged — proves the storefront is transport-agnostic with no `subscription` edit.
- **Backend integration** (`db` fixture): migration up/down/up; storefront draft round-trip — accumulate selection → `/checkout` → resolve via the public endpoint → recomputed line items match; expired token 404; already-redeemed token 404; balance read for a linked vs unlinked chat.
- **fe-user:** `PublicCheckoutView` with `?draft=<token>` fetches the draft, hydrates the fe-core cart, and renders the existing summary with the exact line items (unit + one e2e).
- **Regression:** `subscription` existing suite stays green with `bot_storefront_enabled=false` and with the S45 bridge absent (no import error — D1).

## Sub-sprints

| # | Title | Scope | Gate |
|---|---|---|---|
| **53.0** | Storefront backend | `subscription` `get_bot_commands()` for `/tarifs` `/add-ons` `/tokens` `/checkout`; `subscription_bot_checkout_draft` model + migration; public draft-resolution endpoint; recompute-from-catalog | `--plugin subscription --full` green; bot→draft→public-resolve round-trip green |
| **53.1** | fe-user draft hydration | `PublicCheckoutView` accepts `?draft=<token>` → fetch draft → seed fe-core cart → existing checkout | fe-user lint + unit + e2e green |

## Why this is not overengineering

The storefront reuses everything that already exists: S45's provider-neutral bridge seam (the bot only registers a `BotCommandProvider` and renders `BotReply.choices`), the existing plan/add-on/token-bundle catalogs, the core `LineItemType` vocabulary, and the existing unregistered `PublicCheckoutView` + `checkoutSourceRegistry`. The bot **pre-seeds the cart via a draft link** — it reimplements no checkout, computes no prices on the client, and creates no charge. The only new persistence is one draft table (a generic line-item bag with a one-time token). Core is untouched; the integration is optional and additive; written on neutral DTOs, it serves every future messenger provider for free.

## Cross-references

- **Parent / decision:** [S45 — bot-base bridge](s45-bot-base-bridge.md), decision **D8** (LOCKED 2026-06-06) and the D6/D7 seams this consumes.
- Cart-backed public checkout: [[project_checkout_cart_backed_selections]].
- Plugins live in their own repos: [[feedback_plugins_always_in_own_repos]].
