# Sprint 45 — `telegram_connect`: Telegram bot bridge for vbwd plugins (backend)

**Status:** PLANNED — decisions D1–D5 **LOCKED 2026-06-02** (see §Open decisions). Ready to implement.
**Area:** new backend plugin `telegram_connect` in its own repo `vbwd-plugin-telegram-connect` ([[feedback_plugins_always_in_own_repos]]) **+** fe-admin trio companion `vbwd-fe-admin-plugin-telegram-connect` for bot management (D5 — in scope this sprint, sub-sprint 45.5). No core change — vbwd core stays **agnostic**; all logic lives in the plugin ([[feedback_core_never_depends_on_plugins]]).
**Consumers updated this sprint:** `chat` (llm-chat) gains an optional Telegram interface; `taro` gains its own. Both integrations are **optional** and gated by config — neither plugin hard-depends on Telegram.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). Full, readable variable names — no cryptic abbreviations ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin telegram_connect --full` green = "done" (also re-green `chat` + `taro` after their integration changes). Tables follow the [S43](s43-db-table-naming-normalization.md) convention `telegram_connect_<model>`. Plugin migrations live in the plugin, registered in `alembic.ini` ([[feedback_plugin_migrations_in_plugin]]); revision ids ≤ 32 chars (report 21 gotcha). Baseline `config.json` + `admin-config.json` with at least `debug_mode` ([[feedback_plugin_baseline_config_files]]). Test/demo data only through services, never raw SQL ([[feedback_no_direct_db_for_test_data]]).

## Goal

Give vbwd a **two-way Telegram bridge** that any plugin can plug into, with **no core change**:

1. **Outbound** — vbwd → Telegram. `telegram_connect` **exports a `TelegramService`** (via the DI container) that any plugin can call to **post a message to a channel** or **send a message to a bot chat (DM)**. Example: an invoice-paid notification, a CMS publish announcement, a tarot reading delivered to a subscriber.
2. **Inbound** — Telegram → vbwd. A Telegram user types a command (e.g. `/hello`); Telegram delivers the update to a `telegram_connect` endpoint; `telegram_connect` **dispatches the command to a handler registered by a plugin** and replies through the same bot.
3. **Plugin extensibility** — other plugins register their own bot commands and own ongoing free-text conversations **without** `telegram_connect` knowing anything plugin-specific (dependency inversion). Two concrete consumers ship this sprint:
   - **chat (llm-chat):** `/hello-llm` → bot replies *"Hello, I am `<model-name>`. How may I help you today?"*; thereafter the user's free text in Telegram is the **equivalent of typing in `/dashboard/chat`** — routed through the existing token-billed `ChatService.send_message(user_id, message, history)` and the reply sent back to the chat.
   - **taro:** registers its own command set + interface (e.g. `/draw`, `/reading`) on the same or a separate bot.

## Use cases (acceptance)

- Admin configures a bot token in `telegram_connect`; the bot answers `/hello` with a built-in greeting → confirms the round-trip (inbound dispatch + outbound reply) works.
- A plugin calls `telegram_service.send_to_chat(chat_id, text)` / `send_to_channel(channel, text)` and the message appears in Telegram → confirms the exported service.
- A Telegram user runs `/hello-llm`, gets the model greeting, then sends *"What is 2+2?"* and gets an LLM answer; the user's **linked vbwd token balance is debited** exactly as in the web chat → confirms identity linking + billing reuse.
- A Telegram user runs a `taro` command and gets a reading → confirms a second, independent consumer on the same seam.
- `telegram_connect` **disabled** → `chat` and `taro` still work normally on the web (no hard dependency, no import error).

## Architecture (the two seams)

### Seam A — Outbound: exported `TelegramService` (DI container)

`telegram_connect.on_enable` registers its service in `current_app.container` exactly like other plugins register repos ([[project_plugin_di_provider_registration]], `vbwd/plugins/di_helpers.py::register_repositories`). Consumers resolve it lazily:

```python
container = current_app.container
telegram_service = container.telegram_connect_service()   # provided only when plugin enabled
telegram_service.send_to_chat(chat_id, "Your reading is ready 🔮")
telegram_service.send_to_channel("@my_channel", "New post published")
```

`TelegramService` wraps the Telegram **Bot API** (`https://api.telegram.org/bot<token>/sendMessage`) behind a thin `ITelegramClient` port so it is unit-testable with a fake (no network in tests). Methods (narrow): `send_to_chat(chat_id, text, *, bot=None, parse_mode=None)`, `send_to_channel(channel_id_or_username, text, *, bot=None)`. Multi-bot aware (picks the configured default bot when `bot` is omitted).

### Seam B — Inbound: command dispatch via **dependency inversion** (recommended)

`telegram_connect` must dispatch `/hello-llm` to `chat` and `/draw` to `taro` **without importing them**. Inversion: a plugin opts into Telegram by implementing a tiny optional interface, and `telegram_connect` **collects** providers from the set of enabled plugins at enable/dispatch time. No consumer imports `telegram_connect`; `telegram_connect` imports nothing plugin-specific.

```python
# Optional interface a plugin implements to expose Telegram commands.
class TelegramCommandProvider(Protocol):
    def get_telegram_commands(self) -> list[TelegramCommand]: ...
    # TelegramCommand(command="/hello-llm", handler=callable, description="Start an AI chat")

# A handler receives a normalized inbound message + the resolved vbwd identity (or None)
# and returns a TelegramReply (text to send back) — pure, easily unit-tested.
def handler(ctx: TelegramInbound) -> TelegramReply: ...
```

`telegram_connect`'s `CommandRegistry` is built by asking each **enabled** plugin (via `PluginManager`) whether it implements `get_telegram_commands()`; non-implementers are skipped. Free-text (non-command) messages are routed to whichever plugin currently **owns the conversation** for that Telegram chat (see "conversation mode" below).

> **✅ D1 LOCKED — dependency inversion.** Consumers implement `get_telegram_commands()`; `telegram_connect` collects providers from the enabled-plugin set (via `PluginManager`) at enable/dispatch time. No consumer imports `telegram_connect`; integrations stay optional and `chat`/`taro` keep working when `telegram_connect` is absent. *(Rejected: importable registry singleton — would force a hard `dependencies=["telegram_connect"]`.)*

### Conversation mode (free-text routing)

After `/hello-llm`, the user's *next plain messages* must reach `chat`, not be treated as unknown commands. `telegram_connect` persists a per-chat **active conversation owner** (`telegram_connect_session.active_plugin`, e.g. `"chat"`), set when a command claims the conversation and cleared by `/stop` (built-in) or a timeout. Free text is dispatched to the active owner's message handler; with no active owner, the bot replies with a help/menu.

## Inbound transport (webhook vs polling)

Telegram delivers updates either by **webhook** (Telegram POSTs to a public HTTPS URL) or **long-polling** (`getUpdates` — works behind NAT/firewall, no public URL).

> **✅ D2 LOCKED — webhook (prod) + long-poll worker (dev).** Prod: `POST /api/v1/plugins/telegram-connect/webhook/<bot>`, validated by Telegram's `X-Telegram-Bot-Api-Secret-Token` header against the per-bot `webhook_secret` — no JWT, server-to-server callback. Dev: a long-poll `getUpdates` worker, TESTING/dev-guarded (`if not current_app.config.get("TESTING")`, same pattern as the booking/subscription schedulers) so the round-trip is testable locally with no public HTTPS URL. The poll worker may land in **45.4** to keep 45.0 narrow.

## Identity linking (Telegram account → vbwd user)

Token billing for chat keys on a vbwd `user_id`; a raw Telegram user is anonymous to vbwd. Link them once:

> **✅ D3 LOCKED — deep-link `/start <token>` + anonymous mode.** The dashboard shows a "Connect Telegram" button producing a one-time link token (`POST /link/start`); the user taps the `t.me/<bot>?start=<token>` deep link, and the bot's `/start <token>` binds `telegram_user_id ↔ vbwd user_id`. Commands needing **no** vbwd identity (e.g. a public tarot `/draw`) run **anonymously**; only billed/identity actions (chat) require the link. An unlinked user invoking `/hello-llm` gets a "connect your account first" reply carrying the deep link. *(Rejected: pasted `/link <code>` — more friction, mistype-prone.)*

## Backend design (layered, SOLID)

New plugin `telegram_connect` (new-convention source dir = plugin id):

**Models** (`telegram_connect/telegram_connect/models/`, S43 table names):
| model | table | fields (key) |
|---|---|---|
| `TelegramBot` | `telegram_connect_bot` | `name`, `token` (secret — see Security), `default` bool, `webhook_secret`, `enabled` |
| `TelegramLink` | `telegram_connect_link` | `telegram_user_id`, `vbwd_user_id` (UUID FK to core user), `bot_id`, `linked_at` |
| `TelegramSession` | `telegram_connect_session` | `chat_id`, `bot_id`, `active_plugin` (free-text owner), `updated_at` |

- **Repositories** — `TelegramBotRepository`, `TelegramLinkRepository`, `TelegramSessionRepository` (data access only; registered as DI providers in `on_enable` via `register_repositories`).
- **Services** (DI):
  - `TelegramService` (exported) — outbound send (Seam A), wraps `ITelegramClient`.
  - `WebhookService` / `UpdateDispatcher` — parse an inbound Telegram `Update` → `TelegramInbound`, resolve identity via `TelegramLinkRepository`, resolve the command/active-owner, invoke the handler, send the `TelegramReply`. All business logic here, not in routes.
  - `LinkService` — issue + redeem link tokens (D3).
  - `CommandRegistry` — collects `TelegramCommandProvider`s from enabled plugins (D1).
- **Routes** (`Blueprint("telegram_connect", __name__)`, `get_url_prefix()="/api/v1/plugins/telegram-connect"`):
  - `POST /webhook/<bot>` — inbound updates; **no JWT**, validated by the secret-token header.
  - admin (`require_admin` + `@require_permission("telegram_connect.manage")`): `GET/POST /admin/bots`, `GET/PUT/DELETE /admin/bots/<id>`, `POST /admin/bots/<id>/set-webhook`, `POST /admin/bots/<id>/test` (send a test message).
  - user (`require_auth`): `POST /link/start` → returns a deep-link token; `GET /link` → current link status; `DELETE /link` → unlink.
- **Plugin class** (`__init__.py`) — `metadata(name="telegram-connect", dependencies=[])`, `initialize` merges `DEFAULT_CONFIG`, `get_blueprint`, `get_url_prefix`, `on_enable` (register repos + service in container, register webhook scheduler guarded by TESTING, build `CommandRegistry`), `on_disable` (unregister providers).
- **Migration** `plugins/telegram_connect/migrations/versions/<=32char>_create_telegram.py` (registered in `alembic.ini` `version_locations`).
- **`config.json` + `admin-config.json`** baseline (`debug_mode` + e.g. `default_parse_mode`, `link_token_ttl_seconds`, `poll_interval_seconds`) — copy the shape from an existing correct plugin, never invent.

## Consumer changes this sprint

### chat (llm-chat) — optional Telegram interface
- New config keys (additive to `DEFAULT_CONFIG`): `telegram_enabled` (bool), `telegram_greeting` (default *"Hello, I am {model}. How may I help you today?"*).
- Implement `get_telegram_commands()` returning `/hello-llm` (claims the conversation; replies the greeting with `{model}` from `llm_model`) + a free-text message handler that calls the **existing** `ChatService.send_message(user_id, message, history)` for the **linked** vbwd user and returns the response as the reply. History per Telegram chat is reconstructed from a short server-side window (reuse `max_history_messages`); persisting full TG chat history is out of scope (no-overengineering).
- Unlinked user → reply prompting them to link (D3). No web-chat behavior changes; if `telegram_connect` is disabled, `get_telegram_commands()` is simply never collected.

### taro — own command set
- Implement `get_telegram_commands()` exposing taro's own commands (e.g. `/draw`, `/reading`) backed by taro's existing service. Demonstrates a **second independent consumer** on the same seam; commands needing no billing can run in anonymous mode (D3c).

## Security (CRITICAL)

1. **Bot token is a secret. ✅ D4 LOCKED — encrypted at rest.** Store `TelegramBot.token` encrypted in the DB (reuse the meinchat-style encryption already in the codebase); decrypt only at the moment of calling Telegram. **Never** return the token in any API response (mask to `1234****`). Admin-only write; treat `telegram_connect.manage` like API-key/shell access. *(Rejected: plaintext-admin-only `chat`-precedent — a DB dump would leak live bot control.)*
2. **Webhook authenticity** — validate `X-Telegram-Bot-Api-Secret-Token` against the per-bot `webhook_secret` on every inbound POST; reject otherwise (no open relay).
3. **No unauth side effects** — the webhook only dispatches to registered handlers; unknown commands get a safe canned reply, never an error trace.
4. **Identity** — billed actions require a verified `TelegramLink`; never bill or mutate a vbwd user from an unlinked Telegram id.
5. **Rate limiting / abuse** — cap inbound handling per chat (Telegram itself throttles, but guard the LLM path so a spammy chat can't drain shared resources); honor Telegram's `429 + retry_after` on outbound.
6. **Input bounds** — reuse `chat`'s `max_message_length`; reject oversized inbound text before hitting the LLM.

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock repos + fake `ITelegramClient`):
  - `TelegramService.send_to_chat/send_to_channel` calls the client with the right payload; picks the default bot; surfaces Telegram errors.
  - `UpdateDispatcher`: `/hello` → greeting; unknown command → help; secret-token mismatch → rejected; free text with active owner → routed to that handler; no owner → menu.
  - `LinkService`: issue → redeem binds id; expired token rejected; double-redeem rejected.
  - `CommandRegistry` collects only enabled providers; `chat` greeting interpolates `{model}`; `chat` free-text handler delegates to `ChatService.send_message` with the linked `user_id`; unlinked → link prompt (no billing).
- **Backend integration** (`db` fixture): migration up/down/up; admin bot CRUD + permission enforcement (401/403); webhook POST with valid/invalid secret; full inbound→link→`/hello-llm`→free-text→token-debit round-trip with a fake LLM adapter; taro command round-trip.
- **Consumer regression:** `chat` + `taro` existing suites stay green with `telegram_enabled=false` and with `telegram_connect` absent (no import error).

## Sub-sprints

| # | Title | Scope | Gate |
|---|---|---|---|
| **45.0** | Foundation | plugin skeleton, models+migration, `TelegramService` (Seam A) + exported DI provider, admin bot CRUD, webhook route + secret validation, built-in `/hello`/`/start`/`/stop` | `--plugin telegram_connect --full` green; built-in `/hello` round-trips against a fake client |
| **45.1** | Inbound dispatch + identity | `CommandRegistry` (D1), `UpdateDispatcher`, conversation mode (`TelegramSession`), `LinkService` + link endpoints (D3) | dispatch + linking unit+integration green |
| **45.2** | chat (llm-chat) integration | `telegram_enabled`/`telegram_greeting` config, `get_telegram_commands()` (`/hello-llm` + free-text → `ChatService`), unlinked-prompt | `--plugin chat --full` green; TG-chat round-trip debits tokens |
| **45.3** | taro integration | taro `get_telegram_commands()` for its command set | `--plugin taro --full` green; taro command round-trips |
| **45.4** | Transport hardening (opt.) | long-poll dev worker (TESTING-guarded) + webhook set-up helper; rate-limit guard | green; documented |
| **45.5** | fe-admin trio (D5) | `vbwd-fe-admin-plugin-telegram-connect`: bot CRUD (token masked), set-webhook, test-send, linked-accounts view | fe-admin lint + unit + e2e green |

## fe-admin companion (§10) — ✅ D5 LOCKED: in scope (sub-sprint 45.5)

> **✅ D5 LOCKED — ship the fe-admin trio this sprint (45.5).** Build `vbwd-fe-admin-plugin-telegram-connect` once the backend (45.0–45.3) is green: bot CRUD (token shown masked, set on create/rotate only), "set webhook", "send test message", and a **linked-accounts** view (Telegram id ↔ vbwd user). The user-side "Connect Telegram" deep-link button (D3) belongs in **fe-user** and remains a small separate follow-up (not 45.5).

## Open decisions (summary — all ✅ LOCKED 2026-06-02)

- **D1** ✅ Inbound seam: **dependency-inversion provider interface** (`get_telegram_commands()`; `telegram_connect` collects from enabled plugins; no consumer import).
- **D2** ✅ Transport: **webhook (prod, secret-token header) + TESTING-guarded long-poll worker (dev)**.
- **D3** ✅ Identity linking: **deep-link `/start <token>` + anonymous mode** (link required only for billed/identity actions).
- **D4** ✅ Bot-token storage: **encrypted at rest** (meinchat-style), masked in all API responses, admin-only write.
- **D5** ✅ fe-admin surface: **in scope this sprint as 45.5** (`vbwd-fe-admin-plugin-telegram-connect`); fe-user "Connect Telegram" button is a separate follow-up.

## Why this is not overengineering

`telegram_connect` adds exactly two seams (an exported send-service and an inbound command dispatcher) and reuses everything that already exists: the DI-provider registration pattern, the TESTING-guarded scheduler pattern, the token-billed `ChatService.send_message` (chat path is *not* reimplemented), and taro's existing service. Core is untouched and stays agnostic; consumer integrations are optional and additive.
