# Sprint 45.0 — `bot-base` foundation (provider-neutral bot core)

**Parent:** [S45 — bot-base bridge (umbrella)](s45-bot-base-bridge.md) · **Depends on:** — (keystone) · **Provider-neutral; no transport.**

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** (esp. Open/Closed — this plugin is closed for modification, open for adapter extension) · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING**. Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin bot_base --full` green = "done". Migration in the plugin, registered in `alembic.ini`, revision id ≤ 32 chars ([[feedback_plugin_migrations_in_plugin]]). Baseline `config.json` + `admin-config.json` with `debug_mode` ([[feedback_plugin_baseline_config_files]]). Test data only through services ([[feedback_no_direct_db_for_test_data]]). No core change ([[feedback_core_never_depends_on_plugins]]).

## Scope

The keystone everything else extends. Ships the provider-neutral seam (D1/D6/D7/D10) with **zero transport** — exercised in tests via a **fake `IMessengerProvider`**.

**DTOs / ports** (`bot_base/bot_base/types.py`, `ports.py`): `BotInbound`, `BotReply`, `BotChoice`, `BotIdentity`, `BotCommand`, `ChatRef`; `IMessengerProvider` (SPI), `BotCommandProvider` (consumer interface). See umbrella §Provider abstraction.

**Models** (`bot_base/bot_base/models/`, S43 names):
| model | table | fields (key) |
|---|---|---|
| `BotLink` | `bot_base_link` | `provider_id`, `external_user_id`, `vbwd_user_id` (UUID FK core user), `bot_ref`, `linked_at` |
| `BotSession` | `bot_base_session` | `provider_id`, `chat_ref`, `active_plugin`, `updated_at` |
| `BotLinkToken` | `bot_base_link_token` | `token`, `vbwd_user_id`, `expires_at`, `redeemed_at` (one-time, D3) |

**Repositories** — `BotLinkRepository`, `BotSessionRepository`, `BotLinkTokenRepository` (DI providers via `register_repositories` in `on_enable`).

**Services (DI)** —
- `MessengerProviderRegistry` — the extension point; adapters `register(IMessengerProvider)` here.
- `MessengerService` (exported, Seam A) — provider-routed `send_to_chat(provider_id, chat_ref, text, *, choices=None, ...)`, `send_to_channel(...)`; resolves the provider from the registry; unregistered → clear error.
- `CommandRegistry` — collects `BotCommandProvider`s from enabled plugins via `PluginManager` (D1).
- `UpdateDispatcher` (provider-neutral) — given a `BotInbound`: resolve identity via `BotLinkRepository`, resolve command / active conversation owner / tapped `action_data`, invoke the handler, return/ send the `BotReply`.
- `ConversationService` — get/set/clear active owner in `BotSession`, keyed `(provider_id, chat_ref)`, with idle timeout.
- `LinkService` — issue + redeem one-time link tokens (D3); binds `external_user_id ↔ vbwd_user_id`.
- Built-in command set: `/hello` (greeting), `/start <token>` (redeem link), `/stop` (clear conversation owner), `/help` (menu).

**Routes** (`Blueprint("bot_base", __name__)`, `get_url_prefix()="/api/v1/plugins/bot"`):
- user (`require_auth`): `POST /link/start?provider=<id>` → `{token, deeplink}` (deeplink from the named provider's `build_link_deeplink`); `GET /link` → status; `DELETE /link` → unlink.
- admin (`require_admin` + `@require_permission("bot_base.manage")`): `GET /admin/links` → generic linked-accounts listing (all providers). **No webhook here.**

**Plugin class** — `metadata(name="bot-base", dependencies=[])`; `on_enable` registers repos + `MessengerService` + `MessengerProviderRegistry` + `CommandRegistry` in the container; `on_disable` unregisters. Migration `…/create_bot_base.py`; config (`debug_mode`, `link_token_ttl_seconds`, `conversation_idle_timeout_seconds`).

## TDD plan (tests FIRST — MagicMock repos + a fake `IMessengerProvider`)
- `MessengerService` resolves provider by id and calls `send` with the right payload; unregistered/disabled provider → clear error; picks default when applicable.
- `UpdateDispatcher`: `/hello` → greeting; unknown command → help; free text with active owner → routed to that handler; no owner → menu; a tapped-choice/`action_data` update → routed by namespace to `handle_action`.
- `LinkService`: issue → redeem binds id; expired token rejected; double-redeem rejected.
- `CommandRegistry` collects only enabled providers; `ConversationService` set/clear by claim/`/stop`/timeout.
- **Provider-neutrality:** a stub `BotCommandProvider` driven through the fake provider yields correct `BotReply`s with no transport involved.
- **Integration** (`db` fixture): migration up/down/up; `bot_base.manage` permission enforced on `/admin/links` (401/403); `/link/start`→`/start`→linked round-trip.

## Gate
`--plugin bot_base --full` green; built-in `/hello`·`/start`·`/stop`·`/help` round-trip against the fake provider; link round-trip green.
