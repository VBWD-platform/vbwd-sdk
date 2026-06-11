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

## 2026-06-10 clarifications (owner)

**E2E mechanism = ADAPTIVE on `meinchat-plus` presence** (refined after discovering base meinchat has a *null* device-directory seam — "meinchat-alone has no device keys"; the real device-key E2E crypto is provided by `meinchat-plus` fe+backend):

- **If `meinchat-plus` is installed (fe + backend) → E2E path.** The bot is a real **E2E participant with a server-held keypair**: registered as a **device** in meinchat-plus's `IDeviceDirectory` for the designated bot conversation, so the client's existing per-device wrapping (`_expected_device_ids`) **automatically wraps each message key to the bot device** (ideally no/minimal fe change). The server holds the bot device's **private key encrypted at rest** (reuse `TokenCipher`/the S58.4 `secrets` policy; never plaintext/in a response) and **decrypts the bot's envelope slot** via the registered `IBodyCodec` before `parse_update`. Outbound `send` produces an `e2e_v1` envelope to the conversation devices. Human↔human chats are never read.
- **If `meinchat-plus` is NOT installed → plain path.** The designated bot conversation uses meinchat's server-readable **`plain` protocol** (`body` populated, `envelope` NULL). The bot reads `body` directly and replies in plain. (Acceptable because without the plus E2E layer there is no device-key crypto anyway.)
- **Detection seam:** the adapter selects plain vs e2e from whether a real `IDeviceDirectory`/`IBodyCodec` is registered (i.e. `meinchat-plus` enabled) vs the null fallback — no hard import of meinchat-plus.

**Implementation guidance / scope guard:**
- **Plain path is the primary deliverable this sub-sprint** — it fully proves cross-provider parity NOW (the same `chat` `/hello-llm` round-trips over meinchat with automatic identity, zero consumer change), independent of any deferred crypto.
- **E2E path reuses meinchat-plus's existing device-key crypto** (the bot is just another device + a server-held private key); it must NOT invent crypto or weaken E2E. If the meinchat-plus device-key API isn't ready for a clean bot-device registration + server-side decrypt, implement the plain path fully + the e2e path as far as the plus seam allows, and **FLAG the remaining plus/fe wiring as 45.5.1**.
- Both `--plugin bot_meinchat --full` **and** `--plugin meinchat --full` stay green. The `meinchat` dependency is declared; `meinchat-plus` is an **optional** runtime capability (detected, never hard-imported).
- **Security:** the bot keypair is treated like a bot token (admin-only, encrypted, masked); compromising it exposes only the **bot** conversation, never human↔human chats.

## TDD plan (tests FIRST)
- `MeinchatProvider.parse_update`: a meinchat message in the bot conversation → `BotInbound` with identity resolved from the authenticated sender; a tapped button → `action_data`.
- `send` posts a meinchat message and renders `choices` natively / falls back to a numbered menu.
- Messages **outside** the designated bot conversation are **not** ingested (E2E human chats untouched).
- On enable, `MeinchatProvider` appears in `bot-base`'s registry.
- **Cross-provider integration:** the **same** `chat` `/hello-llm` round-trip that passes over Telegram (45.1/45.2) passes over meinchat with **no consumer change**; identity is automatic (no link step).

## Gate
`--plugin bot_meinchat --full` + `--plugin meinchat --full` green; Telegram **and** meinchat both round-trip `/hello-llm` with the same consumer code; human E2E chats are never read.
