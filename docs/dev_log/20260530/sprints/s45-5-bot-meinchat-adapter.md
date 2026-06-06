# Sprint 45.5 — `bot-meinchat` adapter (second `IMessengerProvider`) — D9

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](s45-0-bot-base-foundation.md) + `meinchat` · **`dependencies=["bot-base", "meinchat"]`.**

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** (Liskov — `MeinchatProvider` is a substitutable `IMessengerProvider`) · **DI** · **DRY** · **NO OVERENGINEERING**. Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin bot_meinchat --full` **and** `--plugin meinchat --full` green. No core change; the `meinchat` dependency is **declared** in `PluginMetadata.dependencies` ([[feedback_core_never_depends_on_plugins]]).

## Why this sub-sprint exists
It **proves** the abstraction (D6/D10): the `chat`/`taro` consumers (and later the S53 storefront) light up *inside* meinchat with **zero consumer edit**. The contrasts with Telegram are the evidence the seam is provider-neutral, not Telegram-shaped.

## Scope

`MeinchatProvider` implements `IMessengerProvider` and self-registers in `on_enable` (`container.messenger_provider_registry().register(MeinchatProvider(...))`).
- **Transport — in-process, no webhook.** Subscribe to meinchat's inbound-message event; call `parse_update` directly. No public HTTPS URL, no secret-token, no poll worker. `send(BotReply)` posts a meinchat message.
- **Identity — automatic.** The meinchat sender is already an authenticated vbwd user → `BotIdentity` resolves directly; no `/start` linking, no `bot_base_link` row. `build_link_deeplink` returns `None`. Billed commands work immediately.
- **Choices — native.** `BotReply.choices` → meinchat message buttons, or a numbered text fallback.
- **E2E caveat (key design point).** meinchat messages are end-to-end encrypted; a server-side dispatcher needs the command in plaintext. Bot interaction runs **only inside a designated bot conversation** whose messages are readable by the bot endpoint (a server participant the client encrypts to / a non-E2E system channel). Normal user↔user E2E chats are **never** read by the bridge; the E2E guarantee for human conversations is unchanged. See [[project_s28_phase1_done_phase2_seams]].

No transport models (in-process); optional config (`debug_mode`, `bot_conversation_id`). Migration only if any persistence is needed (likely none).

**No fe-admin companion.** meinchat has no token, no webhook, and automatic identity (no linked accounts), so its only settings — `enabled`, `bot_conversation_id`, `debug_mode` — ride the generic plugin `admin-config.json` surface. A dedicated `fe-admin-bot-meinchat` is **not** built (add one only if meinchat later grows real config). See [umbrella §Admin / configuration surfaces](s45-bot-base-bridge.md).

## TDD plan (tests FIRST)
- `MeinchatProvider.parse_update`: a meinchat message in the bot conversation → `BotInbound` with identity resolved from the authenticated sender; a tapped button → `action_data`.
- `send` posts a meinchat message and renders `choices` natively / falls back to a numbered menu.
- Messages **outside** the designated bot conversation are **not** ingested (E2E human chats untouched).
- On enable, `MeinchatProvider` appears in `bot-base`'s registry.
- **Cross-provider integration:** the **same** `chat` `/hello-llm` round-trip that passes over Telegram (45.1/45.2) passes over meinchat with **no consumer change**; identity is automatic (no link step).

## Gate
`--plugin bot_meinchat --full` + `--plugin meinchat --full` green; Telegram **and** meinchat both round-trip `/hello-llm` with the same consumer code; human E2E chats are never read.
