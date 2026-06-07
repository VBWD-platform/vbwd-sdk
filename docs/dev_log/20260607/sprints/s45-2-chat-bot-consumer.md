# Sprint 45.2 — chat (llm-chat) bot consumer

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](s45-0-bot-base-foundation.md) (+ [45.1](s45-1-bot-telegram-adapter.md) to demo over Telegram) · **Consumer — binds only to `bot-base` neutral types.**

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** · **DI** · **DRY** · **NO OVERENGINEERING** (reuse the existing token-billed chat path — do **not** reimplement it). Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin chat --full` green; web chat behavior unchanged. No core change.

## Scope

`chat` implements `BotCommandProvider` (`bot_namespace="chat"`) so its commands light up over **every** adapter unchanged.
- New config keys (additive to `DEFAULT_CONFIG`): `bot_enabled` (bool), `bot_greeting` (default *"Hello, I am {model}. How may I help you today?"*).
- `get_bot_commands()` → `/hello-llm`: claims the conversation (sets `chat` as active owner via `bot-base`), replies the greeting with `{model}` from `llm_model`.
- Free-text handler: for the **linked** vbwd user, calls the **existing** `ChatService.send_message(user_id, message, history)` and returns the response as the `BotReply`. History per chat is reconstructed from a short server-side window (reuse `max_history_messages`); persisting full bot-chat history is **out of scope**.
- **Unlinked** user → reply prompting them to link (D3), no billing. If the bridge is disabled, `get_bot_commands()` is simply never collected; web chat is untouched.

## TDD plan (tests FIRST)
- `CommandRegistry` collects `chat` only when `bot_enabled=true`.
- `/hello-llm` greeting interpolates `{model}`; claims the conversation owner.
- Free-text handler delegates to `ChatService.send_message` with the **linked** `user_id`; the reply is the model output; the token balance is debited exactly as in web chat (fake LLM adapter).
- **Unlinked** sender → link prompt, **no** `ChatService` call, **no** debit.
- **Regression:** existing `chat` suite green with `bot_enabled=false` and with the bridge absent (no import error).
- **Integration** (with 45.0/45.1): inbound `/hello-llm` → free text → token-debit round-trip over the fake Telegram client.

## Gate
`--plugin chat --full` green; bot-chat round-trip debits tokens; unlinked path bills nothing; web chat unchanged.
