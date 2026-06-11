# Sprint 71 — iOS: meinchat + meinchat-plus updates for rich bot-choice rendering & styling

**Status:** PLANNED — 2026-06-11. **Companion to [S70](s70-bot-rich-choice-rendering-and-portable-styles.md)** (the backend + web feature). **Area:** the native **meinchat iOS** app and the **meinchat-plus iOS** (E2E) module. **Depends on S70.0** (the `meta` structured-message contract) being green — iOS consumes the **same wire contract** the web client does.

## Why

S70 makes the storefront bot render its choices as **tappable cards** (not a plain numbered list) and makes the look a **portable "bot conversation style."** The wire change is additive: messages gain a nullable **`meta`** JSON field and a public **active-style** endpoint. iOS must learn to (a) render `meta.choices` as native cards, (b) send a tap as `meta.action_data`, and (c) theme the bot conversation from the active style — while **degrading gracefully** (an un-updated app keeps showing the plain numbered `body`).

## Engineering requirements (BINDING)

**TDD-first** (XCTest) · **DevOps-first** · **SOLID** · **DI** · **DRY** · clean code · **NO OVERENGINEERING**. Full, readable names. The iOS gate is the app's own CI (build + XCTest + SwiftLint green). **No change to the S70 wire contract** — iOS is a pure consumer of `meta` + the active-style endpoint. **Backward/forward compatible:** an old app ignores `meta` and renders `body`; a new app ignores unknown `meta.kind` values.

## Wire contract consumed (from S70, do not re-negotiate)

- **Message `meta`** (nullable JSON on a plain message):
  - bot → user: `{ "kind": "bot_choices", "choices": [ {"label","action_data","hint?"} ] }`
  - user → bot (tap): `{ "kind": "bot_action", "action_data": "<plugin>:<action>:<arg>" }` with `body` = the chosen label.
- **Active style:** `GET <meinchat>/bot-conversation-style/active` → `{ name, tokens: { "<token>": "<value>", … } }` (the `--vbwd-botchat-*` set: bubble bg/fg, card bg/border/radius, accent, number-badge, hint, font, spacing).
- Rich choices ride the **plain** bot conversation only (consistent with the adaptive plain/e2e design). E2E (`envelope`) rows are unaffected.

## meinchat iOS — work items

1. **Message model:** add an optional `meta` (decoded as a typed enum: `.botChoices([Choice])`, `.botAction(actionData:)`, `.unknown`) to the `Message` decoding. Unknown/absent `meta` → behave exactly as today (render `body`). XCTest the decode for each shape + the fallback.
2. **Bot choice cards:** when a bot message has `.botChoices`, render native tappable cards (number badge + label + optional `hint`) below the bubble. The plain `body` stays available (accessibility / long-press copy).
3. **Tap → action:** tapping a card sends a message `{ body: label, meta: {kind:"bot_action", action_data} }` through the existing send path (no new transport). The bot replies in the same conversation.
4. **Theming from the active style:** fetch `…/bot-conversation-style/active` (cache + refresh), map the `tokens` to a native `BotChatTheme` (SwiftUI `Color`/corner-radius/spacing/`Font`), and style the cards/bubbles from it. A missing/невалид token falls back to the app default. **No CSS** — a token→native mapping table is the single source.
5. **Graceful fallback & feature flag:** behind a capability check so older servers (no `meta`) and the un-updated app both keep working; never crash on an unknown `meta.kind`.

## meinchat-plus iOS (E2E module) — work items

1. **Pass `meta` through on plain bot conversations.** Bot conversations are plain (server-readable), so `meta` is not encrypted — ensure the plus module's message pipeline **preserves `meta`** end-to-end (decode/forward) rather than dropping it on the plain path. XCTest that a plain message with `meta` survives the plus pipeline unchanged.
2. **(Forward-looking) E2E bot conversations** — when the deferred [S45.5.1](../../20260607/done/s45-5-bot-meinchat-adapter.md) lands (bot as an E2E participant), `meta` must travel **inside** the encrypted envelope (the bot-device decrypt yields `{body, meta}`). Spec the envelope payload as `{body, meta}` now so the future e2e path carries cards too; **not implemented this sprint** (blocked on meinchat-plus Signal decrypt).
3. **Theme parity:** the active-style fetch/apply is **shared** with meinchat iOS (one `BotChatTheme` mapping in a common module) so plus and base render identically.

## TDD plan (XCTest highlights)
- Message `meta` decode: `bot_choices`, `bot_action`, absent, and unknown-`kind` (→ fallback) — no crash.
- Card view renders N cards from `.botChoices`; tap emits the `bot_action` send payload with the right `action_data`.
- `BotChatTheme` maps known tokens; unknown/missing → defaults.
- plus: a plain message carrying `meta` round-trips through the plus pipeline unchanged.

## Out of scope
- The backend/web feature (that is **S70**).
- E2E-encrypted bot conversations (blocked on S45.5.1 / meinchat-plus Signal decrypt) — only the envelope-payload **shape** is reserved here.

## Cross-references
- Backend/web feature & wire contract: [S70](s70-bot-rich-choice-rendering-and-portable-styles.md).
- Adaptive plain/e2e meinchat bot + the deferred e2e decrypt: [S45.5](../../20260607/done/s45-5-bot-meinchat-adapter.md).
- meinchat E2E seams / iOS history: [[project_s28_phase1_done_phase2_seams]].
