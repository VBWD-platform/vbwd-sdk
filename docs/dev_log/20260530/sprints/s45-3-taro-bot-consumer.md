# Sprint 45.3 — taro bot consumer

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](s45-0-bot-base-foundation.md) (+ [45.1](s45-1-bot-telegram-adapter.md) to demo over Telegram) · **Consumer — binds only to `bot-base` neutral types.**

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** · **DI** · **DRY** · **NO OVERENGINEERING** (back the commands with taro's **existing** service — no new reading logic). Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin taro --full` green. No core change.

## Scope

A **second independent consumer** on the same seam, proving the bridge serves more than one plugin.
- New config key (additive): `bot_enabled` (bool).
- `taro` implements `BotCommandProvider` (`bot_namespace="taro"`), `get_bot_commands()` exposing its own commands (e.g. `/draw`, `/reading`) backed by taro's existing service.
- Commands that need **no** billing/identity run in **anonymous** mode (D3c) — no link required. Any billed reading (if applicable) follows the same linked-user rule as chat.
- If the bridge is disabled, `get_bot_commands()` is never collected; taro's web behavior is untouched.

## TDD plan (tests FIRST)
- `CommandRegistry` collects `taro` only when `bot_enabled=true`.
- `/draw` (anonymous) returns a reading `BotReply` via taro's existing service with no link required.
- A multi-step reading that uses `BotReply.choices` routes the tap back through `handle_action` (D7), if taro exposes one.
- **Regression:** existing `taro` suite green with `bot_enabled=false` and with the bridge absent (no import error).
- **Integration** (with 45.0/45.1): inbound `/draw` → reading round-trip over the fake Telegram client.

## Gate
`--plugin taro --full` green; taro command round-trips (anonymous); web behavior unchanged.
