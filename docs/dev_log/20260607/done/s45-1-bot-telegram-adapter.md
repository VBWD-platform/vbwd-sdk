# Sprint 45.1 — `bot-telegram` adapter (first `IMessengerProvider`)

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](s45-0-bot-base-foundation.md) · **`dependencies=["bot-base"]`.**

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** (Liskov — `TelegramProvider` is a substitutable `IMessengerProvider`) · **DI** · **DRY** · **NO OVERENGINEERING**. Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin bot_telegram --full` green. Migration in the plugin, registered in `alembic.ini`, rev id ≤ 32 chars ([[feedback_plugin_migrations_in_plugin]]). Baseline `config.json` + `admin-config.json` (`debug_mode`) ([[feedback_plugin_baseline_config_files]]). Secrets encrypted at rest ([[feedback_plugin_baseline_config_files]] + umbrella §Security D4). No core change.

## Scope

The reference adapter — proves the SPI end-to-end. Implements the Telegram transport and **self-registers** into `bot-base`'s provider registry; `bot-base` and consumers are untouched.

**Models** (`bot_telegram/bot_telegram/models/`):
| model | table | fields (key) |
|---|---|---|
| `TelegramBot` | `bot_telegram_bot` | `name`, `token` (encrypted — D4), `default` bool, `webhook_secret`, `enabled` |

**Services** —
- `TelegramProvider` (`IMessengerProvider`): `parse_update(Telegram Update) → BotInbound` (message **and** `callback_query`); `send(BotReply, to)` → Bot API (renders `BotReply.choices` as an inline keyboard); `build_link_deeplink(token) → "t.me/<bot>?start=<token>"`. The only Telegram-aware class.
- `ITelegramClient` — thin Bot-API wrapper (`https://api.telegram.org/bot<token>/…`) + an in-memory fake for tests (no network). Honors `429 + retry_after`.
- Webhook handler + long-poll dev worker (D2, see Phase 2).

**Repository** — `TelegramBotRepository`.

**Routes** (`Blueprint("bot_telegram", __name__)`, `get_url_prefix()="/api/v1/plugins/bot-telegram"`):
- `POST /webhook/<bot>` — **no JWT**; validate `X-Telegram-Bot-Api-Secret-Token` against the bot's `webhook_secret`; hand raw payload to `TelegramProvider.parse_update` → `bot-base` `UpdateDispatcher`.
- admin (`require_admin` + `@require_permission("bot_telegram.manage")`): `GET/POST /admin/bots`, `GET/PUT/DELETE /admin/bots/<id>`, `POST /admin/bots/<id>/set-webhook`, `POST /admin/bots/<id>/test`. Token always masked in responses.

**Plugin class** — `metadata(name="bot-telegram", dependencies=["bot-base"])`; `on_enable` registers `TelegramBotRepository` **and** `container.messenger_provider_registry().register(TelegramProvider(...))`; `on_disable` unregisters the provider. Config (`debug_mode`, `default_parse_mode`, `poll_interval_seconds`).

### Phase 2 — transport hardening (optional within this sub-sprint)
Long-poll `getUpdates` dev worker, **TESTING/dev-guarded** (`if not current_app.config.get("TESTING")`, same pattern as the booking/subscription schedulers) so the round-trip is testable with no public HTTPS URL; webhook set-up helper; per-`(provider_id, chat_ref)` inbound rate-limit guard. May ship in a follow-up if 45.1 needs to stay narrow.

## 2026-06-10 clarifications (owner)

- **Real Telegram smoke test IS in scope.** In addition to the fake-client CI gate, `/hello` must round-trip over **real Telegram** on the local dev stack. The owner provides a **@BotFather bot token** (stored encrypted via the admin `POST /admin/bots` flow, never committed).
- Therefore **Phase 2's long-poll dev worker is REQUIRED, not optional** — it's the transport for the no-public-HTTPS dev smoke test. TESTING/dev-guarded (`if not current_app.config.get("TESTING")`, booking/subscription-scheduler pattern) so CI/tests never start it. Webhook stays the prod path.
- **`TelegramBot` gains a `username` field** (the bot's `@handle` from BotFather) so `build_link_deeplink` resolves `t.me/<username>?start=<token>` deterministically (the `name` field is the human label, not the deep-link handle).
- **DoD addition:** a manual smoke note (the exact `/hello` round-trip over the real bot via the dev long-poll worker) recorded in the sub-sprint report.

## TDD plan (tests FIRST — fake `ITelegramClient`)
- `TelegramProvider.parse_update`: a text message and a `callback_query` each map to a correct `BotInbound` (command/args/action_data); `send` builds the right payload and renders `choices` as an inline keyboard.
- `build_link_deeplink` → `t.me/<bot>?start=<token>`.
- On enable, `TelegramProvider` appears in `bot-base`'s `MessengerProviderRegistry`.
- **Integration** (`db` fixture): migration up/down/up; admin bot CRUD + permission enforcement (401/403); token never present in any response (masked); webhook POST with **valid** secret dispatches, **invalid** secret → 401; full `/hello` round-trip over the fake client through `bot-base`.

## Gate
`--plugin bot_telegram --full` green; `/hello` round-trips end-to-end over Telegram (fake client); invalid webhook secret rejected; token masked.
