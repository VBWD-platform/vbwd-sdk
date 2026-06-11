# Report 02 (2026-06-11) — Bot rich-choice rendering in meinchat + portable conversation styles (S70) + iOS plan (S71)

**Scope:** make the storefront bot render as **styled cards/menu/cart** in the real meinchat UI (not a plain-text numbered dump), make the look a **portable entity** exportable through the unified S46 Import/Export framework, and plan the iOS counterpart. **Method:** owner-driven, iterative — each ask folded into the sprint doc, then implemented TDD-first via the `vbwd-tdd` agent, gate-green before the next. **On-disk, nothing committed, no core (`vbwd/`) change.** Sprint docs: [`s70`](../../20260610/sprints/s70-bot-rich-choice-rendering-and-portable-styles.md) + [`s71` (iOS)](../../20260610/sprints/s71-ios-meinchat-rich-choice-rendering.md). Walkthrough (real screenshots): [`bot-base-meinchat-walk.html`](../../20260607/reports/bot-base-meinchat-walk.html).

## Why

The S45 storefront bot answered in meinchat as a **plain-text numbered menu** ("1. Starter 2. Pro … Reply with the number") flooded with test-catalog data — because `meinchat_message` carried only `body`/`envelope` text. The earlier walkthrough's tidy cards were report-CSS only; they didn't exist in the UI. This sprint makes the **real** UI render cards.

## How it landed (the iterative asks)

1. "render the choices as cards like the walkthrough" → structured-message capability + card rendering.
2. "the /help / command replies should be nicely styled too" → `bot_menu` kind.
3. "add /cart — a nice cart" → `bot_cart` kind + `/cart`.
4. "also /cart-clear and /cart-edit (tap to remove)" → cart management.
5. "export/import the bot-conversation styles via the unified framework" → `BotConversationStyle` + S46 exchanger.
6. "write an iOS sprint for the meinchat / meinchat-plus updates" → S71.

## The design (provider-neutral)

A generic, nullable **`meta` JSON** on `meinchat_message` carries structured content; the plain `body` stays as the **fallback** for non-rich clients (Liskov — today's iOS is unaffected). Replies carry a provider-neutral **`BotReply.meta`** (`{kind,…}`) that each provider's sender translates. Kinds (all degrade to `body`):
- **`bot_choices`** — choice cards (number badge + label + optional **`hint`** price); `meta.text` is a clean prompt shown instead of the body's numbered list on rich clients. A tapped card sends `{ body:label, meta:{kind:"bot_action", action_data} }`.
- **`bot_menu`** — styled command list (`/help`); tapping a row resends the command.
- **`bot_cart`** — cart card (line items, total, currency, a Proceed-to-checkout affordance); empty-state aware.

**Cart-always-visible (owner, accepted 2026-06-11):** the `subscription` storefront returns a **`bot_cart`** reply after **every add/toggle** (tapping a plan / add-on / token bundle) — not a terse "added" confirmation — so the user always sees the running cart + the **Proceed to checkout** button the moment anything is added. `/cart-edit`'s remove flow keeps its remove-list. Verified live (tap Pro → cart card "Pro ×1 29.00 · Total 29.00 EUR · Proceed to checkout"). `--plugin subscription --full` green; reuses `cart_reply`/`compute_cart`.

All visuals are CSS custom properties (`--vbwd-botchat-*`). The **`BotConversationStyle`** entity (whitelisted token map) is registered as a `BaseModelExchanger` in the **unified S46 framework** (`settings` cluster), so the bot-chat look exports/imports as JSON to another instance; the fe fetches the active style and applies the tokens.

## Sub-sprints (each gate-green)

| # | Plugin(s) | Delivered | Gate |
|---|---|---|---|
| **70.0** | meinchat, bot_meinchat | nullable `meta` JSON + migration; validated `send_text(meta=)`; sender emits `meta.choices`, parse reads `meta.action_data` (tap dispatches directly) | `--plugin meinchat/bot_meinchat --full` ✅ |
| **70.1** | fe-user/meinchat | `MessageBubble` renders `meta.choices` as cards; tap → `sendAction`; `--vbwd-botchat-*` vars + fallbacks | fe-user `--full` + `--plugin meinchat --full` ✅ |
| **70.2** | bot_meinchat | `BotConversationStyle` model+repo+migration; admin CRUD/activate + public active-style route; token whitelist (no CSS injection); **`BaseModelExchanger` in S46** (export→import round-trip) | `--plugin bot_meinchat --full` ✅ |
| **70.3** | bot_base, subscription, bot_meinchat, meinchat | `BotChoice.hint` + `BotReply.meta`; `/help`→`bot_menu`; storefront price hints + clean prompt + `/cart`·`/cart-clear`·`/cart-edit`(+remove); meinchat validates all kinds | all four `--full` ✅ |
| **70.4** | fe-user/meinchat | render `bot_menu`/`bot_cart`, suppress fallback body for known kinds, fetch+apply the active portable style | fe-user `--full` + `--plugin meinchat --full` ✅ |
| **70.5** | — | walkthrough HTML rebuilt with **real** headless captures (menu, priced cards, cart, cart-edit, checkout) | walkthrough updated |
| **S71** | iOS (doc) | meinchat iOS + meinchat-plus iOS plan: native card/menu/cart rendering of `meta`, token→native theme, plus-pipeline `meta` passthrough, graceful fallback; forward-reserve `{body,meta}` envelope for the deferred E2E bot path | planned |

## Verified in the real UI (not a mockup)

Headless captures of the live meinchat / fe-user UI (clean demo catalog): `/help` → styled command menu; `/tarifs`/`/tokens` → priced cards (① Starter €9/mo · ② Pro €29/mo · ③ Business €99/mo); tap → draft; `/cart` → cart card **Total 64.00 EUR** + Proceed to checkout; `/cart-edit` → tap-to-remove; `/checkout` → fe-user checkout with the cart hydrated. All embedded in the walkthrough.

## Documentation

Developer docs written for the rich-message contract:
- `plugins/bot_base/docs/developer/rich-messages.md` — the provider-neutral `BotReply.meta` + `BotChoice.hint` contract, the `meta.kind` vocabulary (`bot_choices`/`bot_menu`/`bot_cart`/`bot_action`), the `/help`→`bot_menu` built-in, and how consumers emit / adapters translate.
- `plugins/meinchat/docs/developer/bot-rich-rendering.md` — the concrete `meinchat_message.meta` capability + validation, the `bot_meinchat` translation, fe-user card/menu/cart rendering, the **cart-always-visible** storefront note, and the portable `BotConversationStyle` (S46-exported).

## Incidental fixes (live dev stack)

- **500 on the bot conversation** — dev DB lacked the new `meta` column + `bot_meinchat_conversation_style` table (migrations had only run in the test DB); applied `alembic upgrade heads` + restarted the backend.
- **Stale vite cache** crashed the meinchat route (`api.ts` served without the new `getActiveBotConversationStyle` export, "App bootstrap failed"); cleared `node_modules/.vite` in `vbwd-fe-user-dev-1` + restarted ([[project_fe_core_dist_vite_cache_staleness]]).
- **Dead fe-user→backend proxy upstream** after the backend restart (nginx marked the upstream down); restarted `vbwd-fe-user-nginx-1`.

## Dev-stack state (reversible)

Storefront catalog deactivated down to the demo set (Starter/Pro/Business · Priority Support/Extra Seats · 1k/5k/20k — `is_active` toggle); `bot-meinchat` + `subscription.bot_storefront_enabled` on; a `Default` `BotConversationStyle` seeded; bot user `assistant` provisioned; the new migrations applied to the dev DB. **Nothing committed** (plugins gitignored, on-disk).

## Deferred / open

- **E2E bot conversations** still blocked on meinchat-plus Signal decrypt (S45.5.1); rich `meta` rides the **plain** path today, and S71 reserves the `{body,meta}` envelope shape for the future e2e path.
- Optional **fe-admin styling UI** for `BotConversationStyle` (today it rides the generic plugin config + the Import/Export surface).
- Packaging of the bot plugins into standalone `vbwd-plugin-*` repos (batched, still pending the owner's go-ahead).
