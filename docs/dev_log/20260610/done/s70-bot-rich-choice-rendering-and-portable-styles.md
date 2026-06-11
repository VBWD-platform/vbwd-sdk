# Sprint 70 — Rich bot-choice rendering in meinchat + portable bot-conversation styles

**Status:** PLANNED — 2026-06-11. **Follow-up to [S45.5 bot-meinchat](../../20260607/done/s45-5-bot-meinchat-adapter.md) + [S53 storefront](../../20260607/done/s53-bot-commerce-storefront.md).** **Area:** `meinchat` + `bot_meinchat` (backend) · `vbwd-fe-user/plugins/meinchat` (frontend) · the unified **S46 data-exchange** framework. iOS is **out of scope here** — see the companion [S71 iOS sprint](s71-ios-meinchat-rich-choice-rendering.md).

## Why

Today the storefront bot answers in meinchat as a **plain-text numbered menu** ("1. Starter 2. Pro 3. Business … Reply with the number") — because `meinchat_message` carries only `body`/`envelope` text and has no structured-choice support. The [S45 walkthrough](../../20260607/reports/bot-base-meinchat-walk.html) rendered those choices as clean **cards** purely in report CSS — that styling does not exist in the real UI. This sprint makes the **real** meinchat conversation render bot choices as **clickable cards**, makes the look a **themeable, portable "bot conversation style"** that exports/imports through the **unified S46 Import/Export interface**, and tidies the demo catalog so the menus are short.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** (Liskov — structured messages are a substitutable extension; plain clients keep working) · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change). Full, readable variable names ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin <name> --full` green on every touched backend plugin, fe-user `--full` (eslint + vue-tsc + vitest) for the frontend = "done". Plugin migrations live in the plugin, registered in `alembic.ini`, rev id ≤ 32 chars ([[feedback_plugin_migrations_in_plugin]]). Tables follow the `meinchat_*` / `bot_meinchat_*` convention. Baseline `config.json` + `admin-config.json` (`debug_mode`) ([[feedback_plugin_baseline_config_files]]). Test/demo data only through services ([[feedback_no_direct_db_for_test_data]]). **No core (`vbwd/`) change** — agnosticism + vocabulary oracles stay green. **Never commit / no repo** without the owner's word.

## Design

### A. Structured interactive messages (the enabling capability)
`meinchat_message` gains a **generic, nullable `meta` JSON column** — structured/interactive content that rides alongside the plain `body` (the `body` stays populated as the human-readable + **fallback** rendering for clients that don't understand `meta`, e.g. today's iOS). For a bot choice prompt:
```json
{ "kind": "bot_choices", "choices": [ {"label": "Pro", "action_data": "subscription:plan:<id>", "hint": "€29/mo"}, … ] }
```
A user **tapping** a card sends a normal message whose `meta` is `{ "kind": "bot_action", "action_data": "subscription:plan:<id>" }` and whose `body` is the label (so the transcript reads naturally and non-rich clients still see what was picked). The plain numbered-text body remains the universal fallback — **Liskov**: a client that ignores `meta` behaves exactly as today.

### B. Card rendering (fe-user)
`MessageBubble.vue` renders `meta.choices` as clickable cards (number badge + label + optional `hint`), and a tap calls the composer to send `{ body: label, meta: {kind:'bot_action', action_data} }`. All visuals come from **CSS custom properties** (`--vbwd-botchat-*`) so the look is themeable, not hard-coded.

### C. Portable "bot conversation style" (the export/import ask)
A first-class entity **`BotConversationStyle`** (`bot_meinchat`): `name`, `is_active`, and a `tokens` JSON mapping the `--vbwd-botchat-*` vars (bubble bg/fg, card bg/border/radius, accent, number-badge color, hint color, font, spacing). Admin CRUD + "set active"; a public read for the fe to fetch the active style and apply the vars. **It registers a `BaseModelExchanger` in the unified S46 framework** (same pattern as shop/cms/discount — `register_*_exchangers(db.session)` in `on_enable`), so **Settings → Import/Export** lists "Bot Conversation Style" and it round-trips JSON/CSV to **another instance** — copy the bot look across instances with the tooling we already built.

## Sub-sprints

| # | Title | Scope | Gate |
|---|---|---|---|
| **70.0** | Structured messages (backend) | `meta` JSON on `meinchat_message` (+ migration); send/list routes accept & return `meta`; `bot_meinchat` sender emits `meta.choices` (body keeps the numbered fallback); `MeinchatProvider.parse_update` reads `meta.action_data` on a tap → dispatches the action | `--plugin meinchat --full` + `--plugin bot_meinchat --full` green; oracles green |
| **70.1** | Choice cards (fe-user) | `MessageBubble` renders `meta.choices` as clickable cards; tap → composer sends `{body, meta:{action_data}}`; `--vbwd-botchat-*` CSS vars; non-rich messages unchanged | fe-user `--full` + 1 e2e green |
| **70.2** | Portable style + data-exchange | `BotConversationStyle` model+repo+migration; admin CRUD/set-active + public get-active route; **`BaseModelExchanger` registered in the unified S46 framework** (settings cluster) — export/import round-trip to another instance | `--plugin bot_meinchat --full` green; data-exchange export→import round-trip green |
| **70.3** | Apply style + clean catalog + real capture | fe-user fetches + applies the active style vars; deactivate the test-data storefront catalog down to the clean demo set (Starter/Pro/Business · Priority Support/Extra Seats · 1k/5k/20k) via services; capture **real** meinchat-UI screenshots of the card-rendered flow; refresh the walkthrough HTML with genuine screenshots | fe-user `--full` green; walkthrough updated with real captures |

## Security / safety
- `meta` is **validated** server-side (shape + a size cap; `action_data` stays opaque + namespaced — the bridge already routes by namespace and the consumer re-checks). A tapped `action_data` is **not trusted** for identity/price — the storefront recomputes server-side exactly as today (S53 §Security).
- The style `tokens` are a **whitelisted** set of CSS-var values (sanitised — no arbitrary CSS injection); the fe applies them as `--vbwd-botchat-*` custom properties only.
- `meta` is additive + nullable; e2e (`envelope`) rows are unaffected (rich choices ride only on **plain** bot conversations — consistent with the adaptive plain/e2e design).

## TDD highlights
- 70.0: a bot choice reply persists `meta.choices` + a fallback numbered `body`; a user message with `meta.action_data` dispatches the action (no number typed); `meta` size/shape validation; migration up/down/up; **regression** — plain messages + e2e rows unchanged; non-`meta` clients still get the numbered body.
- 70.1: `MessageBubble` renders cards from `meta.choices` and emits the tap payload; messages without `meta` render exactly as today.
- 70.2: style CRUD + set-active; the exchanger **exports** the active style and **imports** it into a clean DB (round-trip equality); appears in the data-exchange manifest.
- 70.3: fe applies the active style vars; storefront menus show only the clean demo set.

## 2026-06-11 scope extension (owner)

Verified the cards render in the real meinchat UI; catalog cleaned to the demo set. Owner asked for the full polish + two additions. **The structured-message vocabulary is generalised:** `BotReply` gains an optional **provider-neutral `meta: dict`** (`{kind, …}`) that each provider's sender translates (meinchat → `message.meta`; Telegram → its own formatting / text fallback). New `meta.kind`s — all rendered by `MessageBubble` and all degrading to the plain `body` on non-rich clients:

- **`bot_choices`** (done in 70.0/70.1) — choice cards. **Add:** `BotChoice.hint` (e.g. `"€29/mo"`) shown right-aligned on the card; `meta.text` (a clean prompt) shown **instead of** the body's numbered fallback on card-clients (the numbered list stays in `body` for non-rich clients like today's iOS).
- **`bot_menu`** (NEW) — styled command list. The built-in **`/help`** (bot-base) emits `{kind:"bot_menu", commands:[{command, description}]}`; `MessageBubble` renders a tidy list of command rows; tapping a row sends that command. No more run-on `/help` paragraph.
- **`bot_cart`** (NEW) — styled cart card. New storefront cart commands operate on the **current draft**:
  - **`/cart`** → `{kind:"bot_cart", items:[{name, quantity, unit_price, line_total}], total, currency}` — a nice cart summary (+ a Checkout affordance). `/checkout` may also append a `bot_cart`. Empty draft → a friendly "your cart is empty" state.
  - **`/cart-clear`** → empties the draft; replies with the now-empty `bot_cart` (or a confirmation).
  - **`/cart-edit`** → `bot_choices` titled "Tap any item to remove it" — each draft line is a choice whose `action_data` is a **remove** action (`subscription:remove:<item_type>:<item_id>`); tapping removes that line and replies with the updated edit list (or the empty-cart state). Needs a `remove`-action branch in the storefront `apply_action` + a `clear`/`remove` on the draft service.

**Style application (70.3):** the fe-user fetches `GET /bot-conversation-style/active` and applies the `tokens` as `--vbwd-botchat-*` custom properties (today it only uses the CSS fallbacks). Cards/menus/cart all theme from these vars.

### Extended sub-sprints
| # | Title | Scope | Gate |
|---|---|---|---|
| **70.3** | Rich message kinds (backend) | `BotChoice.hint` + `BotReply.meta` (bot-base, provider-neutral); `/help`→`bot_menu`; storefront price `hint`s + `meta.text` clean prompt; new **`/cart`**→`bot_cart` from the draft; `bot_meinchat` carries `BotReply.meta`→`message.meta` + handles command-row taps; meinchat `meta` validation extended to `bot_menu`/`bot_cart` | `--plugin bot_base/meinchat/bot_meinchat/subscription --full` green |
| **70.4** | Render kinds + apply style (fe-user) | `MessageBubble` renders `bot_menu` (command rows, tap→send command), `bot_cart` (cart card), `bot_choices` hints + `meta.text`; fetch + apply the active portable style vars | fe-user `--full` + e2e green |
| **70.5** | Real capture + walkthrough | re-capture the real meinchat UI (cards + menu + cart + checkout) and refresh the walkthrough HTML with genuine screenshots | walkthrough updated |

## Cross-references
- Unified data-exchange (S46): the `BaseModelExchanger` + `register_*_exchangers` pattern (shop/cms/discount).
- [[reference_admin_config_select_static_only]] · [[project_checkout_cart_backed_selections]] · cart-backed checkout.
- Adaptive plain/e2e meinchat bot ([S45.5](../../20260607/done/s45-5-bot-meinchat-adapter.md)) — rich choices ride the **plain** path.
- iOS counterpart: [S71](s71-ios-meinchat-rich-choice-rendering.md).
